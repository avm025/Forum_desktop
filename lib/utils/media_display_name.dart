import '../models/media_file.dart';

/// Человекочитаемое имя медиа/файла (не серверный hash/код).
///
/// Если имени нет — `"2025-08-06 в 10.54.52"`.
class MediaDisplayName {
  MediaDisplayName._();

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _hexHash = RegExp(r'^[0-9a-fA-F]{10,}$');

  /// Базовое имя (без расширения) выглядит как технический код/hash.
  static bool isTechnicalBaseName(String base) {
    final b = base.trim();
    if (b.isEmpty) return true;
    if (RegExp(r'[а-яА-ЯёЁ\s]').hasMatch(b)) return false;
    if (_uuid.hasMatch(b)) return true;
    if (_hexHash.hasMatch(b)) return true;

    // Обычные «человеческие» префиксы камер/скриншотов.
    if (RegExp(
      r'^(IMG|DSC|DCIM|Screenshot|Screen Shot|photo|image|video|'
      r'document|file|скрин|фото|видео)',
      caseSensitive: false,
    ).hasMatch(b)) {
      return false;
    }

    // Чистый alnum-hash без разделителей (типа a8f3c2b19d4e).
    if (RegExp(r'^[0-9a-zA-Z]+$').hasMatch(b)) {
      final hasDigit = RegExp(r'\d').hasMatch(b);
      final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(b);
      if (hasDigit && hasLetter && b.length >= 10) return true;
      if (hasDigit && b.length >= 12) return true;
      if (!hasDigit && hasLetter && b.length >= 24) return true;
    }

    // Длинные hex/id с подчёркиваниями.
    if (b.length >= 16 &&
        RegExp(r'^[0-9a-fA-F_-]+$').hasMatch(b) &&
        RegExp(r'\d').hasMatch(b)) {
      return true;
    }

    return false;
  }

  static bool isTechnicalFileName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return true;
    final base = name.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    final stem = (dot > 0) ? base.substring(0, dot) : base;
    return isTechnicalBaseName(stem);
  }

  static String formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        'в ${two(local.hour)}.${two(local.minute)}.${two(local.second)}';
  }

  static DateTime? tryParseDttmcr(String? iso) {
    final raw = (iso ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Предпочитает осмысленный `title` / `fname`, иначе дату сообщения.
  static String resolve({
    String? title,
    String? fname,
    String? dttmcr,
    DateTime? at,
  }) {
    for (final candidate in [title, fname]) {
      final t = (candidate ?? '').trim();
      if (t.isNotEmpty && !isTechnicalFileName(t)) return t;
    }
    final dt = at ?? tryParseDttmcr(dttmcr) ?? DateTime.now();
    return formatTimestamp(dt);
  }

  static String forFile(
    MediaFile file, {
    String? dttmcr,
    DateTime? at,
  }) {
    return resolve(
      title: file.title,
      fname: file.fname,
      dttmcr: dttmcr,
      at: at,
    );
  }

  /// Имя для сохранения на диск (с расширением из fname/title, если его нет).
  static String forSave(
    MediaFile file, {
    String? dttmcr,
    DateTime? at,
  }) {
    final label = forFile(file, dttmcr: dttmcr, at: at);
    final cleaned = label.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) return 'document';
    if (cleaned.contains('.')) return cleaned;
    final ext = _extensionOf(file.fname) ?? _extensionOf(file.title);
    if (ext == null || ext.isEmpty) return cleaned;
    return '$cleaned.$ext';
  }

  static String? _extensionOf(String raw) {
    final base = raw.trim().split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot >= base.length - 1) return null;
    final ext = base.substring(dot + 1).trim();
    if (ext.isEmpty || !RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(ext)) {
      return null;
    }
    return ext.toLowerCase();
  }
}
