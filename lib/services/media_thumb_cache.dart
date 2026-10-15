import 'dart:async';
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

  /// Каналы: десятки mp4 без preview — не дёргаем AVFoundation пачкой.
  static const _maxVideoThumbJobs = 2;
  static int _activeVideoJobs = 0;
  static final _videoWaiters = <Completer<void>>[];
  static const _videoThumbTimeout = Duration(seconds: 8);

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

  /// v2: кадр не с t=0 (часто чёрный у канальных mp4), старый кэш не переиспользуем.
  static const _cacheEpoch = 'v2';

  static String cacheKey(MediaFile file) {
    // Локальный путь стабилен на всём пути upload → hash; иначе превью
    // пропадает до «доставлено» и снова генерируется.
    final local = file.URL?.trim() ?? '';
    if (local.isNotEmpty && !local.startsWith('http')) {
      return 'local_${local.hashCode.toRadixString(16)}_$_cacheEpoch';
    }
    final base = () {
      if (file.hash.isNotEmpty) return file.hash;
      if (file.fname.isNotEmpty) {
        final dir = file.fdir.replaceAll('/', '_');
        return '${dir}_${file.fname}';
      }
      if (file.url.isNotEmpty) {
        return file.url.hashCode.toRadixString(16);
      }
      return 'unknown_${file.kind}';
    }();
    return '${base}_$_cacheEpoch';
  }

  /// Поделиться уже готовым JPEG-превью между версиями MediaFile.
  static void alias(MediaFile from, MediaFile to) {
    final existing = peekSync(from);
    if (existing == null) return;
    _knownPaths[cacheKey(to)] = existing.path;
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
      // Чёрный JPEG с t=0 у удалённых/канальных mp4 ~5 КБ — перегенерируем.
      // Локальные video note часто дают компактный валидный кадр — не трогаем.
      final isVideo = file.isVideo || FileKind.isVideoKind(file.kind);
      final local = file.URL?.trim() ?? '';
      final isLocal = local.isNotEmpty && !local.startsWith('http');
      final len = await f.length();
      if (isVideo && !isLocal && len > 0 && len < 9000) {
        try {
          await f.delete();
        } catch (_) {}
        return null;
      }
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

  static Future<void> _acquireVideoSlot() async {
    if (_activeVideoJobs < _maxVideoThumbJobs) {
      _activeVideoJobs++;
      return;
    }
    final waiter = Completer<void>();
    _videoWaiters.add(waiter);
    await waiter.future;
    _activeVideoJobs++;
  }

  static void _releaseVideoSlot() {
    _activeVideoJobs = (_activeVideoJobs - 1).clamp(0, _maxVideoThumbJobs);
    while (_videoWaiters.isNotEmpty && _activeVideoJobs < _maxVideoThumbJobs) {
      final next = _videoWaiters.removeAt(0);
      if (!next.isCompleted) next.complete();
    }
  }

  static Future<void> _ensureVideoThumbnail(MediaFile file, File out) async {
    // Уже готовый локальный JPEG (video note) — просто копируем.
    final localPreview = file.preview.trim();
    if (localPreview.isNotEmpty &&
        !localPreview.startsWith('http') &&
        File(localPreview).existsSync()) {
      await File(localPreview).copy(out.path);
      return;
    }

    if (file.preview.startsWith('http')) {
      try {
        await _downloadPhotoThumbnail(file, out);
        return;
      } catch (_) {
        // fallback — кадр из видео
      }
    }

    if (!VideoConverter.isSupported) {
      // Windows/Linux: кадр рисует InlineVideoPreview; HTTP preview уже пробовали.
      throw UnsupportedError('Video frame extract only on macOS/iOS');
    }

    await _acquireVideoSlot();
    try {
      // СНАЧАЛА локальный mp4 (исходящее видеосообщение). Иначе resolve()
      // собирает http URL по fname → долгий/пустой remote и превью только
      // после доставки.
      final localPath = file.URL?.trim() ?? '';
      if (localPath.isNotEmpty &&
          !localPath.startsWith('http') &&
          File(localPath).existsSync()) {
        await VideoConverter.extractThumbnail(
          inputPath: localPath,
          outputPath: out.path,
        ).timeout(_videoThumbTimeout);
        return;
      }

      final cached = await MediaFileLoader.cachedPathIfExists(file);
      if (cached != null) {
        await VideoConverter.extractThumbnail(
          inputPath: cached,
          outputPath: out.path,
        ).timeout(_videoThumbTimeout);
        return;
      }

      final url = file.url.startsWith('http')
          ? file.url
          : MediaFileUrl.resolve(file);
      if (url.startsWith('http')) {
        await VideoConverter.extractThumbnailFromUrl(
          inputUrl: url,
          outputPath: out.path,
        ).timeout(_videoThumbTimeout);
        return;
      }

      throw StateError('Нет локального видео для превью');
    } finally {
      _releaseVideoSlot();
    }
  }

  static bool needsRemoteThumbnail(MediaFile file) {
    if (!_canGenerateThumbnail(file)) return false;
    // Видео: bytes/URL указывают на mp4 — нужен кадр-превью (в т.ч. локальный).
    if (file.isVideo || FileKind.isVideoKind(file.kind)) {
      return true;
    }
    if (file.bytes != null && file.bytes!.isNotEmpty) return false;
    if (file.URL != null && file.URL!.isNotEmpty) return false;
    return file.url.isNotEmpty || file.preview.startsWith('http');
  }
}
