import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/appearance_settings.dart';

/// Локальное сохранение настроек оформления.
class AppearancePrefs {
  AppearancePrefs._();

  static const _key = 'forum_appearance_v1';

  static Future<AppearanceSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return AppearanceSettings.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AppearanceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
