import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Локальные настройки чатов: mute и архив (серверного mute/archive нет).
class DialogLocalPrefs {
  DialogLocalPrefs._();

  static const _mutedKey = 'forum_dlg_muted_until_v1';
  static const _archivedKey = 'forum_dlg_archived_v1';

  static Future<({Map<String, int> mutedUntil, Set<String> archived})>
      load() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      mutedUntil: _decodeMuted(prefs.getString(_mutedKey)),
      archived: _decodeIds(prefs.getString(_archivedKey)),
    );
  }

  static Future<void> save({
    required Map<String, int> mutedUntil,
    required Set<String> archived,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mutedKey, jsonEncode(mutedUntil));
    await prefs.setString(_archivedKey, jsonEncode(archived.toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mutedKey);
    await prefs.remove(_archivedKey);
  }

  static Map<String, int> _decodeMuted(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return {
        for (final e in map.entries)
          if (e.key.trim().isNotEmpty) e.key.trim(): _asInt(e.value),
      };
    } catch (_) {
      return {};
    }
  }

  static Set<String> _decodeIds(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return {
        for (final e in list)
          if (e.toString().trim().isNotEmpty) e.toString().trim(),
      };
    } catch (_) {
      return {};
    }
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
