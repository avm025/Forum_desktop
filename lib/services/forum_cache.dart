import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Дисковый кэш ответов API — мгновенный показ при старте.
class ForumCache {
  ForumCache._();
  static final ForumCache instance = ForumCache._();

  /// v2: после фикса «удалённые сообщения возвращались из msgs_*.json».
  static const int formatVersion = 2;

  static const _logInUpdatedFile = 'log_in_updated.json';
  static const _catalogFetchedFile = 'catalog_fetched.json';

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
      await _migrateIfNeeded();
      return _dir;
    } catch (_) {
      return null;
    }
  }

  Future<void> _migrateIfNeeded() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final file = File('${dir.path}/cache_format.json');
      var current = 0;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          current = int.tryParse(decoded['version']?.toString() ?? '') ?? 0;
        }
      }
      if (current >= formatVersion) return;

      // Старые msgs_* могли содержать уже удалённые сообщения.
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final base = entity.uri.pathSegments.last;
        if (base.startsWith('msgs_')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      await file.writeAsString(
        jsonEncode({'version': formatVersion}),
        flush: true,
      );
    } catch (_) {}
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
    final catalog = await loadCatalogResponse('database');
    if (catalog != null) return catalog;
    return _readMap('database.json');
  }

  Future<void> saveDatabase(Map<String, dynamic> response) async {
    await _write('database.json', jsonEncode(response));
    await saveCatalogResponse('database', response);
  }

  Future<void> saveLogInUpdated(List<Map<String, dynamic>> entries) async {
    await _write(_logInUpdatedFile, jsonEncode(entries));
  }

  Future<List<dynamic>?> loadLogInUpdated() async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/$_logInUpdatedFile');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> clearLogInUpdated() async {
    await _delete(_logInUpdatedFile);
  }

  /// Ключ файла кэша для метода + тела запроса (`ai_list` с разным `prn_id`).
  String catalogCacheKey(String type, [Map<String, dynamic>? request]) {
    final t = type.trim();
    if (request == null || request.isEmpty) return t;
    final data = request['data'];
    if (data == null) return t;
    final encoded = jsonEncode(data)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (encoded.isEmpty || encoded == 'null' || encoded == '{}') return t;
    // Ограничиваем длину имени файла.
    final suffix =
        encoded.length > 80 ? encoded.substring(0, 80) : encoded;
    return '${t}_$suffix';
  }

  Future<Map<String, dynamic>?> loadCatalogResponse(
    String type, [
    Map<String, dynamic>? request,
  ]) async {
    final key = catalogCacheKey(type, request);
    final wrapped = await _readMap('catalog_$key.json');
    if (wrapped == null) return null;
    final response = wrapped['response'];
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    // Старый формат: весь файл — ответ API.
    if (wrapped['success'] != null || wrapped['data'] != null) {
      return wrapped;
    }
    return null;
  }

  Future<DateTime?> catalogFetchedAt(
    String type, [
    Map<String, dynamic>? request,
  ]) async {
    final key = catalogCacheKey(type, request);
    final wrapped = await _readMap('catalog_$key.json');
    if (wrapped != null) {
      final raw = wrapped['fetched_at']?.toString();
      final fromFile = DateTime.tryParse(raw ?? '');
      if (fromFile != null) return fromFile.toUtc();
    }

    // Method-level дата (как catalog_fetched_* в iOS).
    final meta = await _readMap(_catalogFetchedFile);
    final methodRaw = meta?[type]?.toString();
    final methodDt = DateTime.tryParse(methodRaw ?? '');
    if (methodDt != null) return methodDt.toUtc();

    // Миграция: старый database.json без fetched_at.
    if (type == 'database' && request == null) {
      final dir = await _cacheDir();
      if (dir == null) return null;
      final file = File('${dir.path}/database.json');
      if (await file.exists()) {
        return (await file.lastModified()).toUtc();
      }
    }
    return null;
  }

  Future<void> saveCatalogResponse(
    String type,
    Map<String, dynamic> response, [
    Map<String, dynamic>? request,
  ]) async {
    final key = catalogCacheKey(type, request);
    final now = DateTime.now().toUtc();
    await _write(
      'catalog_$key.json',
      jsonEncode({
        'fetched_at': now.toIso8601String(),
        'response': response,
      }),
    );

    final meta = await _readMap(_catalogFetchedFile) ?? <String, dynamic>{};
    meta[type] = now.toIso8601String();
    await _write(_catalogFetchedFile, jsonEncode(meta));

    if (type == 'database') {
      await _write('database.json', jsonEncode(response));
    }
  }

  /// Кэш свежий относительно серверной метки `updated.dt`.
  ///
  /// [serverUpdatedAt] == null → строки в LOG_IN_UPDATED ещё нет: отдаём кэш.
  Future<Map<String, dynamic>?> loadCatalogIfFresh(
    String type, {
    Map<String, dynamic>? request,
    DateTime? serverUpdatedAt,
  }) async {
    final cached = await loadCatalogResponse(type, request);
    if (cached == null) return null;
    if (serverUpdatedAt == null) return cached;

    final fetched = await catalogFetchedAt(type, request);
    if (fetched == null) return null;
    if (fetched.isBefore(serverUpdatedAt.toUtc())) return null;
    return cached;
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
          if (base.startsWith('msgs_') ||
              base.startsWith('scroll_') ||
              base.startsWith('deleted_msgs_')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// Полный wipe кэша при выходе (как `wipeAllLocalUserData` в Forum_ios).
  Future<void> clearAll() async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> saveMessages(String dlgId, Map<String, dynamic> response) async {
    await _write('msgs_$dlgId.json', jsonEncode(response));
  }

  Future<Map<String, dynamic>?> loadMessages(String dlgId) async {
    return _readMap('msgs_$dlgId.json');
  }

  Future<void> deleteMessagesFile(String dlgId) async {
    await _delete('msgs_$dlgId.json');
  }

  /// Перенос кэша сообщений `msgs_<from>` → `msgs_<to>` (new contact → real id).
  Future<void> migrateMessagesCache(String fromDlgId, String toDlgId) async {
    final from = fromDlgId.trim();
    final to = toDlgId.trim();
    if (from.isEmpty || to.isEmpty || from == to) return;
    final map = await loadMessages(from);
    if (map != null) {
      await saveMessages(to, map);
    }
    await deleteMessagesFile(from);
  }

  /// Локально удалённые id («удалить у себя») — не показывать снова из кэша/сервера.
  Future<Set<String>> loadDeletedMessageIds(String dlgId) async {
    final map = await _readMap('deleted_msgs_$dlgId.json');
    final raw = map?['ids'];
    if (raw is! List) return <String>{};
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Future<void> saveDeletedMessageIds(String dlgId, Set<String> ids) async {
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (clean.isEmpty) {
      await _delete('deleted_msgs_$dlgId.json');
      return;
    }
    await _write(
      'deleted_msgs_$dlgId.json',
      jsonEncode({'ids': clean.toList()}),
    );
  }

  Future<void> addDeletedMessageIds(String dlgId, Iterable<String> ids) async {
    final current = await loadDeletedMessageIds(dlgId);
    current.addAll(ids.map((e) => e.trim()).where((e) => e.isNotEmpty));
    await saveDeletedMessageIds(dlgId, current);
  }

  /// Убрать сообщения из кэша msg_list (после локального удаления).
  Future<void> removeMessagesFromCache(
    String dlgId,
    Iterable<String> ids,
  ) async {
    final idSet = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (idSet.isEmpty) return;

    final map = await loadMessages(dlgId);
    if (map == null) return;

    final data = map['data'];
    if (data is! Map) return;
    final dataMap = Map<String, dynamic>.from(data);
    final msgs = dataMap['msgs'];
    if (msgs is! List) return;

    final filtered = msgs.where((item) {
      if (item is! Map) return true;
      final m = Map<String, dynamic>.from(item);
      final id = m['id']?.toString().trim() ?? '';
      final hash = m['hash']?.toString().trim() ?? '';
      if (id.isNotEmpty && idSet.contains(id)) return false;
      if (hash.isNotEmpty && idSet.contains(hash)) return false;
      return true;
    }).toList();

    dataMap['msgs'] = filtered;
    map['data'] = dataMap;
    await saveMessages(dlgId, map);
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

  Future<void> _delete(String name) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
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
