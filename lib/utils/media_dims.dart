import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import 'file_kind.dart';
import 'media_file_loader.dart';
import 'media_file_url.dart';

/// Подставляет width/height в [MediaFile], если сервер их не прислал.
class MediaDims {
  MediaDims._();

  static final _pending = <String, Future<bool>>{};

  static String _key(MediaFile file) {
    final local = file.URL?.trim() ?? '';
    if (local.isNotEmpty && !local.startsWith('http')) return 'p_$local';
    if (file.hash.isNotEmpty) return 'h_${file.hash}';
    if (file.fname.isNotEmpty) return 'f_${file.fdir}_${file.fname}';
    return 'u_${file.url}';
  }

  /// `true`, если размеры обновились.
  static Future<bool> ensure(MediaFile file) async {
    if (file.widthValue > 0 && file.heightValue > 0) return false;
    final key = _key(file);
    final existing = _pending[key];
    if (existing != null) return existing;
    final future = _ensureImpl(file);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<bool> _ensureImpl(MediaFile file) async {
    if (file.widthValue > 0 && file.heightValue > 0) return false;

    final isVideo = file.isVideo || FileKind.isVideoKind(file.kind);
    if (isVideo) {
      return _fromVideo(file);
    }
    return _fromImage(file);
  }

  static Future<bool> _fromImage(MediaFile file) async {
    try {
      ui.Image? decoded;
      final local = file.URL?.trim() ?? '';
      if (local.isNotEmpty &&
          !local.startsWith('http') &&
          File(local).existsSync()) {
        final bytes = await File(local).readAsBytes();
        decoded = await _decode(bytes);
      } else if (file.bytes != null && file.bytes!.isNotEmpty) {
        decoded = await _decode(file.bytes!);
      } else {
        final path = await MediaFileLoader.cachedPathIfExists(
          file,
          downloadUrl: MediaFileUrl.resolve(file),
        );
        if (path != null) {
          decoded = await _decode(await File(path).readAsBytes());
        }
      }
      if (decoded == null) return false;
      file.width = '${decoded.width}';
      file.height = '${decoded.height}';
      decoded.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<ui.Image?> _decode(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(bytes),
      targetWidth: 64,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<bool> _fromVideo(MediaFile file) async {
    if (kIsWeb) return false;
    VideoPlayerController? controller;
    try {
      final local = file.URL?.trim() ?? '';
      if (local.isNotEmpty &&
          !local.startsWith('http') &&
          File(local).existsSync()) {
        controller = VideoPlayerController.file(File(local));
      } else {
        final cached = await MediaFileLoader.cachedPathIfExists(file);
        if (cached != null) {
          controller = VideoPlayerController.file(File(cached));
        } else {
          final url = MediaFileUrl.resolve(file);
          if (!url.startsWith('http')) return false;
          controller = VideoPlayerController.networkUrl(
            Uri.parse(ApiConfig.rewriteLegacyHost(url)),
            httpHeaders: ApiConfig.fileHeaders,
          );
        }
      }
      await controller.initialize().timeout(const Duration(seconds: 12));
      final size = controller.value.size;
      if (size.width <= 0 || size.height <= 0) return false;
      file.width = '${size.width.round()}';
      file.height = '${size.height.round()}';
      if (file.duration <= 0 && controller.value.duration.inSeconds > 0) {
        file.duration = controller.value.duration.inSeconds;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await controller?.dispose();
      } catch (_) {}
    }
  }
}
