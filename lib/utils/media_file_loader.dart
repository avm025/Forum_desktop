import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import 'media_display_name.dart';

/// Локальный путь или байты вложения для просмотра в чате.
class MediaFileSource {
  final String? localPath;
  final Uint8List? bytes;
  final String networkUrl;

  const MediaFileSource({
    this.localPath,
    this.bytes,
    this.networkUrl = '',
  });

  bool get hasLocalPath => localPath != null && localPath!.isNotEmpty;
  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}

/// Загрузка / кэширование файла с сервера или диска.
class MediaFileLoader {
  MediaFileLoader._();

  static Future<MediaFileSource> resolve(
    MediaFile file, {
    String? downloadUrl,
  }) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return MediaFileSource(bytes: file.bytes, networkUrl: file.url);
    }

    if (file.URL != null && file.URL!.isNotEmpty) {
      final local = File(file.URL!);
      if (await local.exists()) {
        return MediaFileSource(localPath: local.path, networkUrl: file.url);
      }
    }

    final url = (downloadUrl ?? file.url).trim();
    if (url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final cached = await _cacheRemote(file, url);
        return MediaFileSource(
          localPath: cached.path,
          networkUrl: url,
        );
      }
      if (!url.startsWith('http')) {
        final local = File(url);
        if (await local.exists()) {
          return MediaFileSource(localPath: local.path);
        }
      }
    }

    throw StateError('Не удалось получить файл ${file.fname}');
  }

  /// Файл уже локально (кэш / диск / исходящие bytes) — можно открывать как в Telegram.
  static Future<bool> isDownloaded(
    MediaFile file, {
    String? downloadUrl,
  }) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) return true;
    final path = await cachedPathIfExists(file, downloadUrl: downloadUrl);
    return path != null;
  }

  /// Синхронная проверка для DnD: только то, что уже на диске / в памяти.
  static bool hasLocalCopySync(MediaFile file) {
    if (file.bytes != null && file.bytes!.isNotEmpty) return true;
    final path = file.URL?.trim();
    if (path == null || path.isEmpty) return false;
    try {
      final local = File(path);
      return local.existsSync() && local.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Локальный путь, если файл уже в кэше / на диске (без сетевой загрузки).
  static Future<String?> cachedPathIfExists(
    MediaFile file, {
    String? downloadUrl,
  }) async {
    final desired = await _cacheFileFor(file);

    Future<String?> migrateIfNeeded(File existing) async {
      if (!await existing.exists() || await existing.length() <= 0) {
        return null;
      }
      if (existing.path == desired.path) return desired.path;
      if (!await desired.exists() || await desired.length() <= 0) {
        await desired.parent.create(recursive: true);
        await existing.copy(desired.path);
      }
      return desired.path;
    }

    if (file.URL != null && file.URL!.isNotEmpty) {
      final migrated = await migrateIfNeeded(File(file.URL!));
      if (migrated != null) return migrated;
    }

    final url = (downloadUrl ?? file.url).trim();
    if (url.isNotEmpty && !url.startsWith('http')) {
      final migrated = await migrateIfNeeded(File(url));
      if (migrated != null) return migrated;
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (await desired.exists() && await desired.length() > 0) {
        return desired.path;
      }
      final legacy = await _legacyCacheFile(file);
      final migrated = await migrateIfNeeded(legacy);
      if (migrated != null) return migrated;
    }
    return null;
  }

  /// Скачать в кэш (если ещё нет) и вернуть локальный путь.
  static Future<String> ensureCached(
    MediaFile file, {
    String? downloadUrl,
  }) async {
    final existing = await cachedPathIfExists(file, downloadUrl: downloadUrl);
    if (existing != null) return existing;

    final source = await resolve(file, downloadUrl: downloadUrl);
    if (source.hasLocalPath) return source.localPath!;
    if (source.hasBytes) {
      final local = await _cacheFileFor(file);
      await local.writeAsBytes(source.bytes!, flush: true);
      return local.path;
    }
    throw StateError('Не удалось сохранить файл ${file.fname}');
  }

  static Future<File> _cacheFileFor(MediaFile file) async {
    final tempDir = await getTemporaryDirectory();
    final key = _cacheKey(file);
    final dir = Directory('${tempDir.path}/forum_preview/$key');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/${displayFileName(file)}');
  }

  /// Имя на диске = то же, что видно в сообщении.
  static String displayFileName(MediaFile file) {
    return MediaDisplayName.forSave(file);
  }

  static String _cacheKey(MediaFile file) {
    if (file.hash.trim().isNotEmpty) return file.hash.trim();
    final url = file.url.trim();
    if (url.isNotEmpty) {
      return url.hashCode.toUnsigned(32).toRadixString(16);
    }
    final name = displayFileName(file);
    return name.hashCode.toUnsigned(32).toRadixString(16);
  }

  /// Старый плоский путь кэша (fname в корне forum_preview) — для совместимости.
  static Future<File> _legacyCacheFile(MediaFile file) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/forum_preview');
    final legacyName = file.fname.trim().isNotEmpty
        ? file.fname.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : '';
    if (legacyName.isEmpty) {
      return File('${dir.path}/__missing__');
    }
    return File('${dir.path}/$legacyName');
  }

  static Future<File> _cacheRemote(MediaFile file, String url) async {
    final local = await _cacheFileFor(file);

    if (await local.exists() && await local.length() > 0) {
      return local;
    }

    // Переносим из старого имени (hash/fname), если уже скачивали раньше.
    final legacy = await _legacyCacheFile(file);
    if (await legacy.exists() && await legacy.length() > 0) {
      await legacy.copy(local.path);
      return local;
    }

    final response = await http
        .get(
          Uri.parse(url),
          headers: ApiConfig.fileHeaders,
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }

    await local.writeAsBytes(response.bodyBytes, flush: true);
    return local;
  }
}