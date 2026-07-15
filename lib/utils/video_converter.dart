import 'dart:io';

import 'package:flutter/services.dart';

/// Результат нативной конвертации видео (AVFoundation / convertVideo).
class VideoConvertResult {
  final String outputPath;
  final String width;
  final String height;
  final int duration;

  const VideoConvertResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.duration,
  });
}

/// Конвертация видео через platform channel (macOS AVFoundation).
class VideoConverter {
  VideoConverter._();

  static const _channel = MethodChannel('forum_app/video_converter');
  static const _maxVideoSide = 960;

  static bool get isSupported => Platform.isMacOS || Platform.isIOS;

  static Future<VideoConvertResult> compressVideo(String inputPath) async {
    if (!isSupported) {
      throw UnsupportedError('Video conversion is only supported on macOS/iOS');
    }

    final result = await _channel.invokeMethod<Object>('compressVideo', {
      'inputPath': inputPath,
      'maxSide': _maxVideoSide,
    });

    if (result is! Map) {
      throw StateError('Unexpected video converter response');
    }

    final map = Map<Object?, Object?>.from(result);
    final outputPath = map['outputPath']?.toString() ?? '';
    if (outputPath.isEmpty) {
      throw StateError('Video converter returned empty outputPath');
    }

    return VideoConvertResult(
      outputPath: outputPath,
      width: _dimStr(map['width']),
      height: _dimStr(map['height']),
      duration: _parseInt(map['duration']),
    );
  }

  /// Первый кадр видео → JPEG на диск (для превью в чате).
  static Future<String> extractThumbnail({
    required String inputPath,
    required String outputPath,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Video thumbnails only on macOS/iOS');
    }

    final result = await _channel.invokeMethod<Object>('extractThumbnail', {
      'inputPath': inputPath,
      'outputPath': outputPath,
    });

    final path = result?.toString() ?? outputPath;
    if (path.isEmpty) {
      throw StateError('Empty thumbnail path');
    }
    return path;
  }

  /// Первый кадр по URL (без полной загрузки видео).
  static Future<String> extractThumbnailFromUrl({
    required String inputUrl,
    required String outputPath,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Video thumbnails only on macOS/iOS');
    }

    final result = await _channel.invokeMethod<Object>('extractThumbnailFromUrl', {
      'inputUrl': inputUrl,
      'outputPath': outputPath,
    });

    final path = result?.toString() ?? outputPath;
    if (path.isEmpty) {
      throw StateError('Empty thumbnail path');
    }
    return path;
  }

  static String _dimStr(Object? value) {
    if (value == null) return '';
    final v = value is num ? value.toDouble() : double.tryParse(value.toString());
    if (v == null || v <= 0) return '';
    if (v == v.roundToDouble()) return '${v.toInt()}.0';
    return v.toString();
  }

  static int _parseInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
