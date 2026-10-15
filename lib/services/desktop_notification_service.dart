import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Локальные баннеры как в Telegram Desktop (macOS / Linux).
///
/// Сообщения: заголовок — чат, текст — превью (в группе «Имя: текст»).
/// Звонки: заголовок — абонент, текст — «Входящий аудио/видеозвонок».
class DesktopNotificationService {
  DesktopNotificationService._();

  static final DesktopNotificationService instance =
      DesktopNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _seq = 0;

  /// Клик по уведомлению → открыть диалог (`dlg_id`).
  void Function(String dlgId)? onOpenDialog;

  /// Клик по уведомлению о звонке → вывести окно на передний план.
  VoidCallback? onOpenIncomingCall;

  /// Внешний фильтр: false = не показывать баннер сообщения.
  /// [dlgId] — чат уведомления (как Telegram: глушим открытый чат в фокусе).
  bool Function(String dlgId)? allowMessageBanner;

  /// Внешний фильтр: false = не показывать баннер звонка.
  bool Function()? allowCallBanner;

  static const _linuxIconName = 'mail-message-new';

  Future<void> initialize() async {
    if (kIsWeb || _ready) return;
    // Windows toast требует AUMID/GUID в runner; без них plugin может
    // зависнуть на старте — не блокируем UI, баннеры пока только macOS/Linux.
    if (Platform.isWindows) return;
    if (!Platform.isMacOS && !Platform.isLinux) return;

    try {
      await _initializeSupportedPlatforms()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Не мешаем старту приложения.
    }
  }

  Future<void> _initializeSupportedPlatforms() async {
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    final linux = LinuxInitializationSettings(
      defaultActionName: 'Открыть',
      defaultIcon: ThemeLinuxIcon('mail-message-new'),
    );

    final settings = InitializationSettings(
      macOS: darwin,
      linux: linux,
    );

    final ok = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse,
    );
    _ready = ok == true || Platform.isMacOS || Platform.isLinux;

    if (Platform.isMacOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      // ignore: avoid_print
      print('DesktopNotification permission=$granted ready=$_ready');
    }
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload?.trim() ?? '';
    if (payload.startsWith('dlg:')) {
      final id = payload.substring(4).trim();
      if (id.isNotEmpty) onOpenDialog?.call(id);
      return;
    }
    if (payload.startsWith('call:')) {
      onOpenIncomingCall?.call();
    }
  }

  /// Баннер входящего сообщения (не для открытого / своего / замьюченного чата).
  Future<void> showMessage({
    required String dlgId,
    required String chatTitle,
    required String body,
    String? senderName,
    bool isGroup = false,
    bool playSound = true,
    bool force = false,
  }) async {
    if (!_ready) return;
    if (!force &&
        allowMessageBanner != null &&
        !allowMessageBanner!(dlgId)) {
      return;
    }
    final title = chatTitle.trim().isNotEmpty ? chatTitle.trim() : 'Forum';
    var text = body.trim();
    if (text.isEmpty) text = 'Новое сообщение';
    if (isGroup) {
      final sender = (senderName ?? '').trim();
      if (sender.isNotEmpty && !text.startsWith('$sender:')) {
        text = '$sender: $text';
      }
    }

    await _show(
      id: _stableId('msg:$dlgId'),
      title: title,
      body: text,
      payload: 'dlg:$dlgId',
      threadId: dlgId,
      sound: playSound,
    );
  }

  /// Баннер входящего звонка.
  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required bool video,
    String? dlgId,
    bool isGroup = false,
  }) async {
    if (!_ready) return;
    if (allowCallBanner != null && !allowCallBanner!()) return;
    final name = callerName.trim().isNotEmpty ? callerName.trim() : 'Forum';
    final body = video ? 'Входящий видеозвонок' : 'Входящий аудиозвонок';
    await _show(
      id: _stableId('call:$callId'),
      title: name,
      body: body,
      payload: dlgId != null && dlgId.trim().isNotEmpty
          ? 'dlg:${dlgId.trim()}'
          : 'call:$callId',
      threadId: 'call',
      sound: true,
      critical: true,
    );
  }

  Future<void> cancelCall(String callId) async {
    if (!_ready) return;
    await _plugin.cancel(id: _stableId('call:$callId'));
  }

  Future<void> cancelDialog(String dlgId) async {
    if (!_ready) return;
    await _plugin.cancel(id: _stableId('msg:$dlgId'));
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String payload,
    String? threadId,
    bool sound = true,
    bool critical = false,
  }) async {
    try {
      final details = NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: sound,
          // Badge Dock обновляет DockBadgeService по unread, не из баннера.
          presentBadge: false,
          threadIdentifier: threadId,
          interruptionLevel: critical
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
        linux: LinuxNotificationDetails(
          icon: ThemeLinuxIcon(_linuxIconName),
          urgency: critical
              ? LinuxNotificationUrgency.critical
              : LinuxNotificationUrgency.normal,
        ),
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      // ignore: avoid_print
      print('DesktopNotification show failed: $e');
    }
  }

  int _stableId(String key) {
    // Положительный 31-bit id; одинаковый ключ → замена баннера (как в Telegram).
    var hash = 0xcbf29ce484222325;
    for (final c in key.codeUnits) {
      hash ^= c;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    final id = hash & 0x7fffffff;
    if (id != 0) return id;
    _seq = (_seq + 1) & 0x7fffffff;
    return _seq == 0 ? 1 : _seq;
  }
}
