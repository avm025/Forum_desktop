import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/device_id_service.dart';
import '../api/forum_api_client.dart';
import '../calls/call_manager.dart';
import '../firebase_options.dart';

/// Инициализация Firebase / FCM для macOS.
class FirebaseService {
  FirebaseService._();

  static final FirebaseService instance = FirebaseService._();

  String? _fcmToken;
  ForumApiClient? _apiClient;

  String get fcmToken => _fcmToken ?? '';

  /// Привязка API-клиента для повторной отправки `device` при обновлении токена.
  void bindApiClient(ForumApiClient client) {
    _apiClient = client;
  }

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isMacOS) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      _fcmToken = await messaging.getToken();
      messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        CallManager.instance.registerVoipToken(token);
        final api = _apiClient;
        if (api != null && api.isConnected) {
          final uid = await DeviceIdService.getOrCreate();
          await api.sendDeviceData(uid, fcmToken: token);
        }
      });

      // Входящий звонок: data-push поднимает UI (аналог PushKit на iOS).
      FirebaseMessaging.onMessage.listen(_onPush);
      FirebaseMessaging.onMessageOpenedApp.listen(_onPush);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onPush(initial);
    } catch (_) {
      // Firebase/FCM не критичны для работы мессенджера.
    }
  }

  void _onPush(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final type = (data['type'] ?? data['event'] ?? '').toString().toLowerCase();
    final looksLikeCall = type.contains('call') ||
        type.contains('invite') ||
        data.containsKey('call_id') ||
        data['voip'] == true ||
        data['voip'] == '1';
    if (!looksLikeCall) return;
    CallManager.instance.handlePushPayload(data);
  }
}
