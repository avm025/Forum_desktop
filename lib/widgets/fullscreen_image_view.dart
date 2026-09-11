import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../utils/media_file_url.dart';
import 'cached_forum_image.dart';

/// Полноэкранный просмотр фото из чата.
class FullscreenImageViewer extends StatelessWidget {
  final MediaFile file;

  const FullscreenImageViewer({super.key, required this.file});

  static Future<void> show(BuildContext context, MediaFile file) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => FullscreenImageViewer(file: file),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width - 32;
    final maxH = size.height - 80;
    final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
    final preview = file.preview.trim();
    final resolved = MediaFileUrl.resolve(file);
    final localPath = file.URL?.trim() ?? '';
    // Полный файл важнее preview — иначе мелькает мелкое превью/заглушка.
    final networkUrl = resolved.isNotEmpty
        ? resolved
        : ((preview.startsWith('http://') || preview.startsWith('https://'))
            ? preview
            : '');

    final thumb = MediaThumbCache.peekSync(file);
    Widget? thumbPlaceholder;
    if (thumb != null) {
      thumbPlaceholder = Image.file(
        thumb,
        fit: BoxFit.contain,
        width: maxW,
        height: maxH,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    Widget image;
    if (hasBytes) {
      image = Image.memory(
        file.bytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync || frame != null) return child;
          return thumbPlaceholder ?? const SizedBox.shrink();
        },
      );
    } else if (localPath.isNotEmpty &&
        !localPath.startsWith('http') &&
        File(localPath).existsSync()) {
      image = Image.file(
        File(localPath),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync || frame != null) return child;
          return thumbPlaceholder ?? const SizedBox.shrink();
        },
      );
    } else if (networkUrl.isNotEmpty) {
      image = CachedForumImage(
        url: networkUrl,
        width: maxW,
        height: maxH,
        fit: BoxFit.contain,
        blankWhileLoading: true,
        placeholder: thumbPlaceholder,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
      );
    } else if (thumbPlaceholder != null) {
      image = thumbPlaceholder;
    } else {
      image = const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: image,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
