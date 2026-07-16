import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Дисковый кэш ответов API — мгновенный показ при старте.
class ForumCache {
  ForumCache._();
  static final ForumCache instance = ForumCache._();

  Directory? _dir;

  Future<Directory?> _cacheDir() async {
    if (kIsWeb) return null;
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationDocumentsDirectory();
      _dir = Directory('${base.path}/forum_cache');
      if (!await _dir!.exists()) {
        await _dir!.create(recursive: true);
      }
      return _dir;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDialogs(Map<String, dynamic> response) async {
    await _write('dialogs.json', jsonEncode(response));
  }

  Future<Map<String, dynamic>?> loadDialogs() async {
    return _readMap('dialogs.json');
  }

  Future<void> saveGroups(Map<String, dynamic> response) async {
    await _write('groups.json', jsonEncode(response));
  }

  Future<Map<String, dynamic>?> loadGroups() async {
    return _readMap('groups.json');
  }

  Future<Map<String, dynamic>?> loadDatabase() async {
    return _readMap('database.json');
  }

  Future<void> saveDatabase(Map<String, dynamic> response) async {
    await _write('database.json', jsonEncode(response));
  }

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    await _write('profile.json', jsonEncode(profile));
  }

  Future<Map<String, dynamic>?> loadProfile() async {
    return _readMap('profile.json');
  }

  Future<void> clearSessionData() async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      for (final name in ['dialogs.json', 'groups.json', 'profile.json']) {
        final file = File('${dir.path}/$name');
        if (await file.exists()) await file.delete();
      }
      await for (final entity in dir.list()) {
        if (entity is File) {
          final base = entity.uri.pathSegments.last;
          if (base.startsWith('msgs_') || base.startsWith('scroll_')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> saveMessages(String dlgId, Map<String, dynamic> response) async {
    await _write('msgs_$dlgId.json', jsonEncode(response));
  }

  Future<Map<String, dynamic>?> loadMessages(String dlgId) async {
    return _readMap('msgs_$dlgId.json');
  }

  Future<void> saveScrollAnchor(String dlgId, Map<String, dynamic> anchor) async {
    await _write('scroll_$dlgId.json', jsonEncode(anchor));
  }

  Future<Map<String, dynamic>?> loadScrollAnchor(String dlgId) async {
    return _readMap('scroll_$dlgId.json');
  }

  Future<void> _write(String name, String content) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      await File('${dir.path}/$name').writeAsString(content, flush: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readMap(String name) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/$name');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }
}
