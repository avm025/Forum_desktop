import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_logger.dart';
import 'file_kind.dart';
import 'video_converter.dart';

/// Результат подготовки медиа перед upload (как Global.resizeImage / convertVideo).
class PreparedUploadMedia {
  final Uint8List bytes;
  final String fileName;
  final String width;
  final String height;
  final int duration;

  const PreparedUploadMedia({
    required this.bytes,
    required this.fileName,
    this.width = '',
    this.height = '',
    this.duration = 0,
  });
}

class _PhotoPrepArgs {
  final String? path;
  final Uint8List? bytes;
  final String originalName;
  final int maxSide;
  final int jpegQuality;

  const _PhotoPrepArgs({
    this.path,
    this.bytes,
    required this.originalName,
    required this.maxSide,
    required this.jpegQuality,
  });
}

class _PhotoPrepResult {
  final Uint8List jpeg;
  final String fileName;
  final String width;
  final String height;
  final int sourceBytes;

  const _PhotoPrepResult({
    required this.jpeg,
    required this.fileName,
    required this.width,
    required this.height,
    required this.sourceBytes,
  });
}

/// Fallback (не macOS): decode/resize в isolate.
_PhotoPrepResult _preparePhotoIsolate(_PhotoPrepArgs args) {
  late final Uint8List raw;
  if (args.path != null && args.path!.isNotEmpty) {
    raw = File(args.path!).readAsBytesSync();
  } else if (args.bytes != null && args.bytes!.isNotEmpty) {
    raw = args.bytes!;
  } else {
    throw StateError('Нет данных файла для подготовки');
  }

  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw StateError('Не удалось декодировать изображение ${args.originalName}');
  }

  final resized = _fitMaxSideSync(decoded, args.maxSide);
  final jpeg = Uint8List.fromList(
    img.encodeJpg(resized, quality: args.jpegQuality),
  );

  final base = args.originalName.contains('.')
      ? args.originalName.substring(0, args.originalName.lastIndexOf('.'))
      : args.originalName;

  return _PhotoPrepResult(
    jpeg: jpeg,
    fileName: '$base.jpg',
    width: resized.width.toString(),
    height: resized.height.toString(),
    sourceBytes: raw.length,
  );
}

img.Image _fitMaxSideSync(img.Image source, int maxSide) {
  final w = source.width;
  final h = source.height;
  if (w <= maxSide && h <= maxSide) return source;
  if (w >= h) {
    return img.copyResize(source, width: maxSide);
  }
  return img.copyResize(source, height: maxSide);
}

/// Подготовка фото/видео к upload (WS_MSG_MEDIA.md).
class MediaPreprocessor {
  MediaPreprocessor._();

  static const _maxPhotoSide = 1280;
  static const _jpegQuality = 50; // iOS compressionQuality 0.5
  static const _hdMaxPhotoSide = 2560;
  static const _hdJpegQuality = 85;
  static const _uuid = Uuid();

  static Future<PreparedUploadMedia> prepare({
    required String originalName,
    Uint8List? bytes,
    String? path,
    bool noCompression = false,
    bool highQuality = false,
  }) async {
    final kind = FileKind.kindFromName(originalName);
    if (FileKind.isVideoKind(kind)) {
      // Видеосообщения (noCompression): без перекодирования — превью сразу.
      if (noCompression) {
        return _prepareVideoPassthrough(
          originalName: originalName,
          bytes: bytes,
          path: path,
        );
      }
      return _prepareVideo(originalName: originalName, bytes: bytes, path: path);
    }
    if (noCompression) {
      return _preparePhotoUncompressed(
        originalName: originalName,
        bytes: bytes,
        path: path,
      );
    }
    final maxSide = highQuality ? _hdMaxPhotoSide : _maxPhotoSide;
    final quality = highQuality ? _hdJpegQuality : _jpegQuality;
    return _preparePhoto(
      bytes: bytes,
      path: path,
      originalName: originalName,
      maxSide: maxSide,
      jpegQuality: quality,
    );
  }

  /// Без сжатия: исходные байты как есть.
  static Future<PreparedUploadMedia> _preparePhotoUncompressed({
    required String originalName,
    Uint8List? bytes,
    String? path,
  }) async {
    Uint8List raw;
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      raw = await File(path).readAsBytes();
    } else if (bytes != null && bytes.isNotEmpty) {
      raw = bytes;
    } else {
      throw StateError('Нет данных файла для подготовки');
    }
    var width = '';
    var height = '';
    if (path != null && path.isNotEmpty && Platform.isMacOS) {
      final dims = await _sipsPixelSize(path);
      width = dims.$1;
      height = dims.$2;
    }
    ApiLogger.instance.logEvent(
      'MEDIA',
      'photo(raw): ${raw.length} bytes, ${width}×$height',
    );
    return PreparedUploadMedia(
      bytes: raw,
      fileName: originalName,
      width: width,
      height: height,
    );
  }

  /// Фото: на macOS — `sips` (нативно, без зависания на скринах Retina).
  /// Иначе — isolate + package:image.
  static Future<PreparedUploadMedia> _preparePhoto({
    required String originalName,
    Uint8List? bytes,
    String? path,
    int maxSide = _maxPhotoSide,
    int jpegQuality = _jpegQuality,
  }) async {
    await Future<void>.delayed(Duration.zero);

    String? localPath =
        (path != null && path.isNotEmpty && await File(path).exists())
            ? path
            : null;

    File? tempInput;
    try {
      if (localPath == null && bytes != null && bytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final ext = FileKind.extensionFromName(originalName);
        tempInput = File(
          '${dir.path}/forum_in_${_uuid.v4()}.${ext.isEmpty ? 'png' : ext}',
        );
        await tempInput.writeAsBytes(bytes, flush: true);
        localPath = tempInput.path;
      }

      // Уже сжатый JPEG из native clipboard — только прочитать, без sips/decode.
      if (localPath != null) {
        final lower = localPath.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
          final len = await File(localPath).length();
          if (len > 0 && len < 3 * 1024 * 1024) {
            final dims = Platform.isMacOS
                ? await _sipsPixelSize(localPath)
                : ('', '');
            final maxDim = [
              int.tryParse(dims.$1) ?? 0,
              int.tryParse(dims.$2) ?? 0,
            ].fold<int>(0, (a, b) => a > b ? a : b);
            if (maxDim > 0 && maxDim <= maxSide) {
              final jpeg = await File(localPath).readAsBytes();
              final base = originalName.contains('.')
                  ? originalName.substring(0, originalName.lastIndexOf('.'))
                  : originalName;
              ApiLogger.instance.logEvent(
                'MEDIA',
                'photo(ready-jpeg): ${jpeg.length} bytes, ${dims.$1}×${dims.$2}',
              );
              return PreparedUploadMedia(
                bytes: jpeg,
                fileName: '$base.jpg',
                width: dims.$1,
                height: dims.$2,
              );
            }
          }
        }
      }

      if (localPath != null && Platform.isMacOS) {
        try {
          return await _preparePhotoViaSips(
            inputPath: localPath,
            originalName: originalName,
            maxSide: maxSide,
            jpegQuality: jpegQuality,
          );
        } catch (e) {
          ApiLogger.instance.logEvent('MEDIA', 'sips failed, fallback: $e');
        }
      }

      final result = await compute(
        _preparePhotoIsolate,
        _PhotoPrepArgs(
          path: localPath,
          bytes: localPath == null ? bytes : null,
          originalName: originalName,
          maxSide: maxSide,
          jpegQuality: jpegQuality,
        ),
      );

      ApiLogger.instance.logEvent(
        'MEDIA',
        'photo(isolate): ${result.sourceBytes} → ${result.jpeg.length} bytes, '
        '${result.width}×${result.height}',
      );

      return PreparedUploadMedia(
        bytes: result.jpeg,
        fileName: result.fileName,
        width: result.width,
        height: result.height,
      );
    } finally {
      if (tempInput != null && await tempInput.exists()) {
        try {
          await tempInput.delete();
        } catch (_) {}
      }
    }
  }

  /// Нативный ресайз через macOS `sips` — не грузит Dart isolate огромным PNG.
  static Future<PreparedUploadMedia> _preparePhotoViaSips({
    required String inputPath,
    required String originalName,
    int maxSide = _maxPhotoSide,
    int jpegQuality = _jpegQuality,
  }) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/forum_up_${_uuid.v4()}.jpg';
    final sourceLen = await File(inputPath).length();

    final resize = await Process.run(
      'sips',
      [
        '-Z',
        '$maxSide',
        '-s',
        'format',
        'jpeg',
        '-s',
        'formatOptions',
        '$jpegQuality',
        inputPath,
        '--out',
        outPath,
      ],
      runInShell: false,
    );

    if (resize.exitCode != 0 || !await File(outPath).exists()) {
      final err = '${resize.stderr}'.trim();
      throw StateError(
        'sips failed (${resize.exitCode})${err.isEmpty ? '' : ': $err'}',
      );
    }

    final jpeg = await File(outPath).readAsBytes();
    final dims = await _sipsPixelSize(outPath);

    try {
      await File(outPath).delete();
    } catch (_) {}

    final base = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;

    ApiLogger.instance.logEvent(
      'MEDIA',
      'photo(sips): $sourceLen → ${jpeg.length} bytes, '
      '${dims.$1}×${dims.$2}',
    );

    return PreparedUploadMedia(
      bytes: jpeg,
      fileName: '$base.jpg',
      width: dims.$1,
      height: dims.$2,
    );
  }

  static Future<(String, String)> _sipsPixelSize(String path) async {
    final r = await Process.run(
      'sips',
      ['-g', 'pixelWidth', '-g', 'pixelHeight', path],
      runInShell: false,
    );
    if (r.exitCode != 0) return ('', '');
    final out = '${r.stdout}';
    final w = RegExp(r'pixelWidth:\s*(\d+)').firstMatch(out)?.group(1) ?? '';
    final h = RegExp(r'pixelHeight:\s*(\d+)').firstMatch(out)?.group(1) ?? '';
    return (w, h);
  }

  /// Видео без перекодирования (video note / noCompression).
  static Future<PreparedUploadMedia> _prepareVideoPassthrough({
    required String originalName,
    Uint8List? bytes,
    String? path,
  }) async {
    Uint8List out;
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      out = await File(path).readAsBytes();
    } else if (bytes != null && bytes.isNotEmpty) {
      out = bytes;
    } else {
      throw StateError('Нет данных видео для отправки');
    }
    return PreparedUploadMedia(
      bytes: out,
      fileName: _mp4Name(originalName),
    );
  }

  /// Видео: mp4, max 960 px через AVFoundation (macOS) / convertVideo.
  static Future<PreparedUploadMedia> _prepareVideo({
    required String originalName,
    Uint8List? bytes,
    String? path,
  }) async {
    if (!VideoConverter.isSupported) {
      throw UnsupportedError(
        'Конвертация видео поддерживается только на macOS/iOS',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final id = _uuid.v4();
    final ext = FileKind.extensionFromName(originalName).isEmpty
        ? 'mp4'
        : FileKind.extensionFromName(originalName);

    File? inputFile;
    var wroteTempInput = false;
    File? outputFile;

    try {
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        inputFile = File(path);
      } else {
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Нет данных файла для подготовки');
        }
        inputFile = File('${tempDir.path}/forum_in_$id.$ext');
        await inputFile.writeAsBytes(bytes, flush: true);
        wroteTempInput = true;
      }

      final converted = await VideoConverter.compressVideo(inputFile.path);
      outputFile = File(converted.outputPath);
      final outBytes = await outputFile.readAsBytes();

      ApiLogger.instance.logEvent(
        'MEDIA',
        'video: → ${outBytes.length} bytes, ${converted.width}×${converted.height}, '
        '${converted.duration}s',
      );

      return PreparedUploadMedia(
        bytes: outBytes,
        fileName: _mp4Name(originalName),
        width: converted.width,
        height: converted.height,
        duration: converted.duration,
      );
    } finally {
      if (wroteTempInput && inputFile != null && await inputFile.exists()) {
        await inputFile.delete();
      }
      if (outputFile != null && await outputFile.exists()) {
        await outputFile.delete();
      }
    }
  }

  static String _mp4Name(String originalName) {
    final base = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;
    return '$base.mp4';
  }
}
