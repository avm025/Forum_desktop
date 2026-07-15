import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/device_id_service.dart';
import '../api/forum_api_client.dart';
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
      );

      _fcmToken = await messaging.getToken();
      messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        final api = _apiClient;
        if (api != null && api.isConnected) {
          final uid = await DeviceIdService.getOrCreate();
          await api.sendDeviceData(uid, fcmToken: token);
        }
      });
    } catch (_) {
      // Firebase/FCM не критичны для работы мессенджера.
    }
  }
}
