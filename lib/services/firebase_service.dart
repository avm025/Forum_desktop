import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/device_id_service.dart';
import '../api/forum_api_client.dart';
import '../calls/call_manager.dart';
import '../firebase_options.dart';
import '../models/notification_settings.dart' as forum_notif;
import 'api_logger.dart';
import 'desktop_notification_service.dart';

/// Top-level handler: data-only FCM, когда UI-isolate не активен (фон).
/// Alert-push с `notification`/`aps.alert` показывает сама система (APNs).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {}
  await DesktopNotificationService.instance.initialize();
  await FirebaseService.showRemoteMessageAsBanner(message, force: true);
}

/// Инициализация Firebase / FCM для macOS.
///
/// Offline (api_forum_doc): сервер шлёт FCM/APNs только если в `usr_device`
/// непустой `token` + `msg_push_on` / `msg_pop_ups_on`. Нужны APNs entitlement
/// и подпись Apple Development (Team в Xcode).
class FirebaseService {
  FirebaseService._();

  static final FirebaseService instance = FirebaseService._();

  static const _tokenPrefsKey = 'forum_fcm_token_v1';

  String? _fcmToken;
  ForumApiClient? _apiClient;
  forum_notif.NotificationSettings? _notifications;
  bool _pendingDeviceSend = false;
  Timer? _tokenRetryTimer;

  String get fcmToken => _fcmToken ?? '';

  bool get hasUsableToken => fcmToken.isNotEmpty;

  /// Привязка API-клиента для повторной отправки `device` при обновлении токена.
  void bindApiClient(ForumApiClient client) {
    _apiClient = client;
  }

  /// Актуальные msg_* для payload `device` (из AppState).
  void bindNotificationSettings(forum_notif.NotificationSettings settings) {
    _notifications = settings;
  }

  /// Любой data-push не про звонок (новое сообщение / группа и т.п.).
  VoidCallback? onChatRelatedPush;

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isMacOS) return;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
        provisional: false,
      );
      ApiLogger.instance.logEvent(
        'FCM',
        'permission=${settings.authorizationStatus}',
      );

      // Последний известный token — пока APNs не готов.
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_tokenPrefsKey)?.trim() ?? '';
      if (cached.isNotEmpty) {
        _fcmToken = cached;
        ApiLogger.instance.logEvent('FCM', 'cached token ok(${cached.length})');
      }

      messaging.onTokenRefresh.listen((token) async {
        await _setToken(token);
        ApiLogger.instance.logEvent('FCM', 'token refresh len=${token.length}');
        CallManager.instance.registerVoipToken(token);
        _pendingDeviceSend = true;
        await flushDeviceRegistration();
      });

      FirebaseMessaging.onMessage.listen(_onPush);
      FirebaseMessaging.onMessageOpenedApp.listen(_onPush);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onPush(initial);

      // APNs/token — в фоне, без блокировки UI.
      unawaited(() async {
        await _waitForApnsToken(messaging);
        await _refreshToken(messaging);
      }());

      // APNs часто приходит позже первого getToken — ретраи.
      _tokenRetryTimer?.cancel();
      _tokenRetryTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (hasUsableToken) return;
        await _waitForApnsToken(messaging, attempts: 4);
        await _refreshToken(messaging);
        if (hasUsableToken) {
          _pendingDeviceSend = true;
          await flushDeviceRegistration();
        }
      });
    } catch (e) {
      ApiLogger.instance.logEvent('FCM', 'init failed: $e');
    }
  }

  Future<void> _refreshToken(FirebaseMessaging messaging) async {
    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _setToken(token);
        CallManager.instance.registerVoipToken(token);
        _pendingDeviceSend = true;
        await flushDeviceRegistration();
      }
      ApiLogger.instance.logEvent(
        'FCM',
        'token=${hasUsableToken ? "ok(${fcmToken.length})" : "empty — нужен Push + Team в Xcode"}',
      );
    } catch (e) {
      ApiLogger.instance.logEvent('FCM', 'getToken failed: $e');
    }
  }

  Future<void> _setToken(String token) async {
    _fcmToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefsKey, token);
  }

  Future<void> _waitForApnsToken(
    FirebaseMessaging messaging, {
    int attempts = 20,
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final apns = await messaging.getAPNSToken();
        if (apns != null && apns.isNotEmpty) {
          ApiLogger.instance.logEvent('FCM', 'apns ready');
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    ApiLogger.instance.logEvent(
      'FCM',
      'apns not ready — offline push не будет без Push Notifications + Apple Team',
    );
    await _logNativeApnsFile();
  }

  /// Лог AppDelegate в sandbox-контейнере: Library/Logs/forum_apns.log
  Future<void> _logNativeApnsFile() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final candidates = <String>[
        '$home/Library/Logs/forum_apns.log',
        '$home/Library/Containers/forum.me/Data/Library/Logs/forum_apns.log',
      ];
      File? file;
      for (final path in candidates) {
        final f = File(path);
        if (await f.exists()) {
          file = f;
          break;
        }
      }
      if (file == null) {
        ApiLogger.instance.logEvent(
          'FCM',
          'native apns log missing — AppDelegate не писал didRegister/didFail',
        );
        return;
      }
      final lines = await file.readAsLines();
      final tail = lines.length <= 8 ? lines : lines.sublist(lines.length - 8);
      for (final line in tail) {
        if (line.trim().isEmpty) continue;
        ApiLogger.instance.logEvent('FCM', 'native: $line');
      }
    } catch (e) {
      ApiLogger.instance.logEvent('FCM', 'native apns log read failed: $e');
    }
  }

  /// Повторная отправка WS `device` с token + msg_* (force).
  Future<void> flushDeviceRegistration() async {
    final api = _apiClient;
    final token = _fcmToken ?? '';
    if (api == null || !api.isConnected) {
      _pendingDeviceSend = true;
      return;
    }
    try {
      final uid = await DeviceIdService.getOrCreate();
      await api.sendDeviceData(
        uid,
        fcmToken: token,
        notifications: _notifications,
        force: true,
      );
      _pendingDeviceSend = false;
      ApiLogger.instance.logEvent(
        'FCM',
        'device sent tokenLen=${token.length} '
        'pushOn=${_notifications?.pushOn} popUps=${_notifications?.popUpsOn}',
      );
    } catch (e) {
      _pendingDeviceSend = true;
      ApiLogger.instance.logEvent('FCM', 'device send failed: $e');
    }
  }

  /// Вызвать после успешного `log_in`.
  /// Сервер вяжет FCM token к `uid` устройства через WS `device`;
  /// если сокета нет — шлёт push на этот token.
  Future<void> onLoggedIn({
    forum_notif.NotificationSettings? notifications,
  }) async {
    if (notifications != null) _notifications = notifications;
    try {
      final messaging = FirebaseMessaging.instance;
      if (!hasUsableToken) {
        await _waitForApnsToken(messaging, attempts: 16);
        await _refreshToken(messaging);
      } else {
        // Token уже есть — всё равно досылаем device с актуальным uid/token.
        _pendingDeviceSend = true;
        await flushDeviceRegistration();
      }
    } catch (e) {
      ApiLogger.instance.logEvent('FCM', 'onLoggedIn failed: $e');
      await flushDeviceRegistration();
    }
  }

  void _onPush(RemoteMessage message) {
    unawaited(showRemoteMessageAsBanner(message));
    onChatRelatedPush?.call();
  }

  /// Показ баннера из FCM (foreground / background / opened).
  static Future<void> showRemoteMessageAsBanner(
    RemoteMessage message, {
    bool force = false,
  }) async {
    final data = Map<String, dynamic>.from(message.data);
    final type = (data['type'] ?? data['event'] ?? '').toString().toLowerCase();
    final looksLikeCall = type.contains('call') ||
        type.contains('invite') ||
        data.containsKey('call_id') ||
        data['voip'] == true ||
        data['voip'] == '1';
    if (looksLikeCall) {
      if (!force) {
        CallManager.instance.handlePushPayload(data);
      }
      return;
    }

    final n = message.notification;
    final title =
        (n?.title ?? data['title'] ?? data['name'] ?? data['fr_name'] ?? '')
            .toString()
            .trim();
    final body =
        (n?.body ?? data['body'] ?? data['text'] ?? '').toString().trim();
    final dlgId = (data['dlg_id'] ??
            data['dlgId'] ??
            data['grp_id'] ??
            data['chat_id'] ??
            '')
        .toString()
        .trim();

    // Data-only без текста — всё равно показать, иначе offline «тихий» push
    // не виден пользователю.
    if (title.isEmpty && body.isEmpty && data.isEmpty) return;

    await DesktopNotificationService.instance.showMessage(
      dlgId: dlgId.isNotEmpty ? dlgId : 'fcm',
      chatTitle: title.isNotEmpty ? title : 'Forum',
      body: body.isNotEmpty ? body : 'Новое сообщение',
      isGroup: false,
      force: force,
    );
  }
}
