import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../utils/file_kind.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';
import '../utils/video_converter.dart';

/// Дисковый кэш превью медиа в сообщениях (фото + первый кадр видео).
class MediaThumbCache {
  MediaThumbCache._();

  static final _pending = <String, Future<File>>{};
  static final _knownPaths = <String, String>{};
  static String? _basePath;

  static Future<Directory> _cacheDir() async {
    if (_basePath != null) {
      return Directory(_basePath!);
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/forum_media_thumbs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _basePath = dir.path;
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

  static void _remember(File file, MediaFile media) {
    _knownPaths[cacheKey(media)] = file.path;
  }

  /// Синхронный peek для DnD-превью (путь уже известен после показа в чате).
  static File? peekSync(MediaFile file) {
    final key = cacheKey(file);
    final remembered = _knownPaths[key];
    if (remembered != null) {
      try {
        final f = File(remembered);
        if (f.existsSync() && f.lengthSync() > 0) return f;
      } catch (_) {}
    }
    final base = _basePath;
    if (base == null) return null;
    final f = File('$base/$key.jpg');
    try {
      if (f.existsSync() && f.lengthSync() > 0) {
        // sync peek — без async validate; build перезагрузит при ошибке decode
        _knownPaths[key] = f.path;
        return f;
      }
    } catch (_) {}
    return null;
  }

  static Future<File?> getIfExists(MediaFile file) async {
    final f = await _cacheFile(file);
    if (await f.exists() && await f.length() > 0) {
      if (await _isValidImageFile(f)) {
        _remember(f, file);
        return f;
      }
      try {
        await f.delete();
      } catch (_) {}
    }
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
    if (!_canGenerateThumbnail(file)) {
      throw StateError('Нет превью для ${file.fname}');
    }

    final out = await _cacheFile(file);
    if (await out.exists() && await out.length() > 0) {
      if (await _isValidImageFile(out)) {
        _remember(out, file);
        return out;
      }
      try {
        await out.delete();
      } catch (_) {}
    }

    if (file.isVideo || FileKind.isVideoKind(file.kind)) {
      await _ensureVideoThumbnail(file, out);
      _remember(out, file);
      return out;
    }

    await _downloadPhotoThumbnail(file, out);
    if (!await _isValidImageFile(out)) {
      try {
        await out.delete();
      } catch (_) {}
      throw StateError('Ответ не является изображением');
    }
    _remember(out, file);
    return out;
  }

  static bool _canGenerateThumbnail(MediaFile file) {
    if (file.isVideo || FileKind.isVideoKind(file.kind)) return true;
    final name = file.fname.isNotEmpty ? file.fname : file.title;
    return FileKind.isImageKind(file.kind) || FileKind.isImageName(name);
  }

  static Future<bool> _isValidImageFile(File file) async {
    try {
      final raf = await file.open();
      final header = await raf.read(12);
      await raf.close();
      if (header.length < 3) return false;
      // JPEG
      if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
        return true;
      }
      // PNG
      if (header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47) {
        return true;
      }
      // GIF
      if (header.length >= 3 &&
          header[0] == 0x47 &&
          header[1] == 0x49 &&
          header[2] == 0x46) {
        return true;
      }
      // WEBP
      if (header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _downloadPhotoThumbnail(MediaFile file, File out) async {
    final url = _photoSourceUrl(file);
    if (url.isEmpty) {
      throw StateError('Нет URL для превью фото');
    }

    final response = await http
        .get(
          Uri.parse(url),
          headers: ApiConfig.fileHeaders,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    await out.writeAsBytes(response.bodyBytes, flush: true);
  }

  static String _photoSourceUrl(MediaFile file) {
    final preview = file.preview.trim();
    if (preview.startsWith('http')) return preview;
    return MediaFileUrl.resolve(file);
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
    if (!_canGenerateThumbnail(file)) return false;
    if (file.bytes != null && file.bytes!.isNotEmpty) return false;
    if (file.URL != null && file.URL!.isNotEmpty) return false;
    return file.url.isNotEmpty || file.preview.startsWith('http');
  }
}
