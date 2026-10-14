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
    void Function(double? progress)? onProgress,
  }) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      onProgress?.call(1);
      return MediaFileSource(bytes: file.bytes, networkUrl: file.url);
    }

    if (file.URL != null && file.URL!.isNotEmpty) {
      final local = File(file.URL!);
      if (await local.exists()) {
        onProgress?.call(1);
        return MediaFileSource(localPath: local.path, networkUrl: file.url);
      }
    }

    final url = (downloadUrl ?? file.url).trim();
    if (url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final cached = await _cacheRemote(
          file,
          url,
          onProgress: onProgress,
        );
        return MediaFileSource(
          localPath: cached.path,
          networkUrl: url,
        );
      }
      if (!url.startsWith('http')) {
        final local = File(url);
        if (await local.exists()) {
          onProgress?.call(1);
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
      if (!await _looksLikeExpectedMedia(file, existing)) {
        return null;
      }
      if (existing.path == desired.path) return desired.path;
      if (!await desired.exists() || await desired.length() <= 0) {
        await desired.parent.create(recursive: true);
        await existing.copy(desired.path);
      } else if (!await _looksLikeExpectedMedia(file, desired)) {
        await desired.delete();
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
        if (await _looksLikeExpectedMedia(file, desired)) {
          return desired.path;
        }
        try {
          await desired.delete();
        } catch (_) {}
      }
      final legacy = await _legacyCacheFile(file);
      final migrated = await migrateIfNeeded(legacy);
      if (migrated != null) return migrated;
    }
    return null;
  }

  /// Скачать в кэш (если ещё нет) и вернуть локальный путь.
  /// [onProgress]: `0…1` или `null` (размер неизвестен).
  static Future<String> ensureCached(
    MediaFile file, {
    String? downloadUrl,
    void Function(double? progress)? onProgress,
  }) async {
    final existing = await cachedPathIfExists(file, downloadUrl: downloadUrl);
    if (existing != null) {
      onProgress?.call(1);
      return existing;
    }

    final source = await resolve(
      file,
      downloadUrl: downloadUrl,
      onProgress: onProgress,
    );
    if (source.hasLocalPath) {
      onProgress?.call(1);
      return source.localPath!;
    }
    if (source.hasBytes) {
      final local = await _cacheFileFor(file);
      await local.writeAsBytes(source.bytes!, flush: true);
      onProgress?.call(1);
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

  static Future<File> _cacheRemote(
    MediaFile file,
    String url, {
    void Function(double? progress)? onProgress,
  }) async {
    final local = await _cacheFileFor(file);
    final resolvedUrl = ApiConfig.rewriteLegacyHost(url.trim());

    if (await local.exists() && await local.length() > 0) {
      if (await _looksLikeExpectedMedia(file, local)) {
        onProgress?.call(1);
        return local;
      }
      // Битый/чужой кэш (часто JPEG-превью или HTML 401 под именем видео).
      try {
        await local.delete();
      } catch (_) {}
    }

    // Переносим из старого имени (hash/fname), если уже скачивали раньше.
    final legacy = await _legacyCacheFile(file);
    if (await legacy.exists() && await legacy.length() > 0) {
      if (await _looksLikeExpectedMedia(file, legacy)) {
        await legacy.copy(local.path);
        onProgress?.call(1);
        return local;
      }
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(resolvedUrl));
      request.headers.addAll(ApiConfig.fileHeaders);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      final tmp = File('${local.path}.part');
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      final sink = tmp.openWrite();
      var received = 0;
      final head = <int>[];
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (head.length < 64) {
            final need = 64 - head.length;
            head.addAll(chunk.length <= need ? chunk : chunk.sublist(0, need));
          }
          if (onProgress != null) {
            if (total != null && total > 0) {
              onProgress((received / total).clamp(0.0, 1.0));
            } else {
              onProgress(null);
            }
          }
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        try {
          await sink.close();
        } catch (_) {}
        try {
          await tmp.delete();
        } catch (_) {}
        rethrow;
      }

      if (received <= 0) {
        try {
          await tmp.delete();
        } catch (_) {}
        throw StateError('Пустой ответ сервера');
      }
      // Сервер иногда отдаёт HTML/JSON ошибки с кодом 200.
      if (_looksLikeHtmlOrJson(Uint8List.fromList(head))) {
        try {
          await tmp.delete();
        } catch (_) {}
        throw StateError('Сервер вернул не медиафайл');
      }

      await tmp.rename(local.path);
      onProgress?.call(1);
      return local;
    } finally {
      client.close();
    }
  }

  /// Видео не должно быть JPEG/PNG; иначе это превью под чужим именем.
  static Future<bool> _looksLikeExpectedMedia(MediaFile file, File local) async {
    try {
      final raf = await local.open();
      final header = await raf.read(16);
      await raf.close();
      if (header.isEmpty) return false;

      final isJpeg = header.length >= 3 &&
          header[0] == 0xFF &&
          header[1] == 0xD8 &&
          header[2] == 0xFF;
      final isPng = header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47;
      final isGif = header.length >= 3 &&
          header[0] == 0x47 &&
          header[1] == 0x49 &&
          header[2] == 0x46;
      final isHtml = header[0] == 0x3C /* < */ ||
          (header.length >= 5 &&
              String.fromCharCodes(header.take(5)).toLowerCase() == '<!doc');

      if (isHtml) return false;

      if (file.isAudio) {
        // JPEG/PNG вместо аудио — битый кэш.
        if (isJpeg || isPng || isGif) return false;
        // MP3 frame / ID3
        if (header.length >= 3 &&
            header[0] == 0x49 &&
            header[1] == 0x44 &&
            header[2] == 0x33) {
          return true;
        }
        // AAC/M4A/MP4 audio: ftyp
        if (header.length >= 8 &&
            String.fromCharCodes(header.sublist(4, 8)) == 'ftyp') {
          return true;
        }
        // MPEG frame sync
        if (header.length >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
          return true;
        }
        return !isJpeg && !isPng && !isGif;
      }

      if (file.isVideo) {
        if (isJpeg || isPng || isGif) return false;
        // MP4/MOV: ftyp box often at offset 4.
        if (header.length >= 8) {
          final box = String.fromCharCodes(header.sublist(4, 8));
          if (box == 'ftyp') return true;
        }
        // WebM / Matroska EBML
        if (header.length >= 4 &&
            header[0] == 0x1A &&
            header[1] == 0x45 &&
            header[2] == 0xDF &&
            header[3] == 0xA3) {
          return true;
        }
        // Неизвестный контейнер, но явно не картинка — пробуем играть.
        return true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeHtmlOrJson(List<int> bytes) {
    if (bytes.isEmpty) return false;
    // Skip BOM / whitespace
    var i = 0;
    while (i < bytes.length &&
        (bytes[i] == 0x20 ||
            bytes[i] == 0x0A ||
            bytes[i] == 0x0D ||
            bytes[i] == 0x09)) {
      i++;
    }
    if (i >= bytes.length) return false;
    final c = bytes[i];
    return c == 0x3C /* < */ || c == 0x7B /* { */ || c == 0x5B /* [ */;
  }
}