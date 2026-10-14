import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_settings.dart';

/// Локальное кэширование настроек уведомлений (desktop + офлайн).
class NotificationSettingsPrefs {
  NotificationSettingsPrefs._();

  static const _key = 'forum_notification_settings_v2';

  static Future<NotificationSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return NotificationSettings.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(NotificationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
