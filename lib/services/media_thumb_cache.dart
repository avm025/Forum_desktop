import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/media_file.dart';
import '../utils/media_file_loader.dart';
import '../utils/video_converter.dart';

/// Дисковый кэш превью медиа в сообщениях (фото + первый кадр видео).
class MediaThumbCache {
  MediaThumbCache._();

  static final _pending = <String, Future<File>>{};

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/forum_media_thumbs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String cacheKey(MediaFile file) {
    if (file.hash.isNotEmpty) return file.hash;
    if (file.fname.isNotEmpty) {
      final dir = file.fdir.replaceAll('/', '_');
      return '${dir}_${file.fname}';
    }
    if (file.url.isNotEmpty) {
      return file.url.hashCode.toRadixString(16);
    }
    return 'unknown_${file.kind}';
  }

  static Future<File> _cacheFile(MediaFile file) async {
    final dir = await _cacheDir();
    return File('${dir.path}/${cacheKey(file)}.jpg');
  }

  static Future<File?> getIfExists(MediaFile file) async {
    final f = await _cacheFile(file);
    if (await f.exists() && await f.length() > 0) return f;
    return null;
  }

  /// Превью из кэша или загрузка/генерация один раз.
  static Future<File> ensureThumbnail(MediaFile file) async {
    final cached = await getIfExists(file);
    if (cached != null) return cached;

    final key = cacheKey(file);
    final inFlight = _pending[key];
    if (inFlight != null) return inFlight;

    final future = _ensureImpl(file);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<File> _ensureImpl(MediaFile file) async {
    final out = await _cacheFile(file);
    if (await out.exists() && await out.length() > 0) return out;

    if (file.isVideo) {
      await _ensureVideoThumbnail(file, out);
      return out;
    }

    await _downloadPhotoThumbnail(file, out);
    return out;
  }

  static Future<void> _downloadPhotoThumbnail(MediaFile file, File out) async {
    final url = _photoSourceUrl(file);
    if (url.isEmpty) {
      throw StateError('Нет URL для превью фото');
    }

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    await out.writeAsBytes(response.bodyBytes, flush: true);
  }

  static String _photoSourceUrl(MediaFile file) {
    if (file.preview.startsWith('http')) return file.preview;
    if (file.url.startsWith('http')) return file.url;
    return '';
  }

  static Future<void> _ensureVideoThumbnail(MediaFile file, File out) async {
    if (file.preview.startsWith('http')) {
      try {
        await _downloadPhotoThumbnail(file, out);
        return;
      } catch (_) {
        // fallback — первый кадр
      }
    }

    if (!VideoConverter.isSupported) {
      throw UnsupportedError('Извлечение кадра видео доступно только на macOS/iOS');
    }

    if (file.url.startsWith('http')) {
      try {
        await VideoConverter.extractThumbnailFromUrl(
          inputUrl: file.url,
          outputPath: out.path,
        );
        return;
      } catch (_) {
        // fallback — локальный файл
      }
    }

    final source = await MediaFileLoader.resolve(file);
    if (!source.hasLocalPath) {
      throw StateError('Не удалось получить видеофайл');
    }

    await VideoConverter.extractThumbnail(
      inputPath: source.localPath!,
      outputPath: out.path,
    );
  }

  static bool needsRemoteThumbnail(MediaFile file) {
    if (file.bytes != null && file.bytes!.isNotEmpty) return false;
    if (file.URL != null && file.URL!.isNotEmpty) return false;
    return file.url.isNotEmpty || file.preview.startsWith('http');
  }
}
