import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_logger.dart';
import 'file_kind.dart';
import 'image_dimensions.dart';
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

/// Подготовка фото/видео к upload (WS_MSG_MEDIA.md).
class MediaPreprocessor {
  MediaPreprocessor._();

  static const _maxPhotoSide = 1280;
  static const _jpegQuality = 50; // iOS compressionQuality 0.5
  static const _uuid = Uuid();

  static Future<PreparedUploadMedia> prepare({
    required String originalName,
    Uint8List? bytes,
    String? path,
  }) async {
    final kind = FileKind.kindFromName(originalName);
    if (FileKind.isVideoKind(kind)) {
      return _prepareVideo(originalName: originalName, bytes: bytes, path: path);
    }
    return _preparePhoto(bytes: bytes, path: path, originalName: originalName);
  }

  /// Фото: fit в 1280×1280, JPEG quality 0.5.
  static Future<PreparedUploadMedia> _preparePhoto({
    required String originalName,
    Uint8List? bytes,
    String? path,
  }) async {
    final raw = await _readBytes(bytes: bytes, path: path);
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw StateError('Не удалось декодировать изображение $originalName');
    }

    final resized = _fitMaxSide(decoded, _maxPhotoSide);
    final jpeg = Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
    final dims = ImageDimensions(resized.width.toDouble(), resized.height.toDouble());

    ApiLogger.instance.logEvent(
      'MEDIA',
      'photo: ${raw.length} → ${jpeg.length} bytes, ${dims.widthStr}×${dims.heightStr}',
    );

    return PreparedUploadMedia(
      bytes: jpeg,
      fileName: _jpgName(originalName),
      width: dims.widthStr,
      height: dims.heightStr,
    );
  }

  /// Видео: mp4, max 960 px через AVFoundation (macOS) / convertVideo.
  static Future<PreparedUploadMedia> _prepareVideo({
    required String originalName,
    Uint8List? bytes,
    String? path,
  }) async {
    if (!VideoConverter.isSupported) {
      throw UnsupportedError('Конвертация видео поддерживается только на macOS/iOS');
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
        final raw = await _readBytes(bytes: bytes, path: path);
        inputFile = File('${tempDir.path}/forum_in_$id.$ext');
        await inputFile.writeAsBytes(raw, flush: true);
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

  static img.Image _fitMaxSide(img.Image source, int maxSide) {
    final w = source.width;
    final h = source.height;
    if (w <= maxSide && h <= maxSide) return source;
    if (w >= h) {
      return img.copyResize(source, width: maxSide);
    }
    return img.copyResize(source, height: maxSide);
  }

  static Future<Uint8List> _readBytes({
    Uint8List? bytes,
    String? path,
  }) async {
    if (bytes != null && bytes.isNotEmpty) return bytes;
    if (path != null && path.isNotEmpty) {
      return File(path).readAsBytes();
    }
    throw StateError('Нет данных файла для подготовки');
  }

  static String _jpgName(String originalName) {
    final base = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;
    return '$base.jpg';
  }

  static String _mp4Name(String originalName) {
    final base = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;
    return '$base.mp4';
  }
}
