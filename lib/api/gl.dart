import '../services/forum_cache.dart';

/// Метка актуальности справочника из `log_in.updated[]`.
class LogInUpdatedEntry {
  final String type;
  final DateTime dt;

  const LogInUpdatedEntry({required this.type, required this.dt});

  Map<String, dynamic> toJson() => {
        'type': type,
        'dt': dt.toUtc().toIso8601String(),
      };

  static LogInUpdatedEntry? fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString().trim() ?? '';
    if (type.isEmpty) return null;
    final raw = json['dt']?.toString().trim() ?? '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    return LogInUpdatedEntry(type: type, dt: dt.toUtc());
  }
}

/// Глобальное состояние клиента (аналог iOS `GL`).
class GL {
  GL._();

  /// Справочники, для которых действует кэш по `LOG_IN_UPDATED`.
  static const catalogTypes = {'ai_list', 'database', 'emoji'};

  /// Массив `updated` из последнего успешного `log_in`.
  static List<LogInUpdatedEntry> LOG_IN_UPDATED = [];

  static DateTime? updatedAt(String type) {
    final key = type.trim();
    for (final e in LOG_IN_UPDATED) {
      if (e.type == key) return e.dt;
    }
    return null;
  }

  /// Разбор `log_in.updated` → память + диск.
  static Future<void> applyLogInUpdated(dynamic raw) async {
    final list = <LogInUpdatedEntry>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final entry =
            LogInUpdatedEntry.fromJson(Map<String, dynamic>.from(item));
        if (entry != null) list.add(entry);
      }
    }
    LOG_IN_UPDATED = list;
    await ForumCache.instance.saveLogInUpdated(
      list.map((e) => e.toJson()).toList(),
    );
  }

  static Future<void> loadPersisted() async {
    final raw = await ForumCache.instance.loadLogInUpdated();
    if (raw == null) return;
    final list = <LogInUpdatedEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final entry =
          LogInUpdatedEntry.fromJson(Map<String, dynamic>.from(item));
      if (entry != null) list.add(entry);
    }
    LOG_IN_UPDATED = list;
  }

  static Future<void> clear() async {
    LOG_IN_UPDATED = [];
    await ForumCache.instance.clearLogInUpdated();
  }
}
