import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_file.dart';
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
    final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
    final preview = file.preview.trim();
    final resolved = MediaFileUrl.resolve(file);
    final localPath = file.URL?.trim() ?? '';

    Widget image;
    if (hasBytes) {
      image = Image.memory(file.bytes!, fit: BoxFit.contain);
    } else if (localPath.isNotEmpty &&
        !localPath.startsWith('http') &&
        File(localPath).existsSync()) {
      image = Image.file(File(localPath), fit: BoxFit.contain);
    } else if (preview.startsWith('http://') || preview.startsWith('https://')) {
      image = CachedForumImage(
        url: preview,
        width: size.width - 32,
        height: size.height - 80,
        fit: BoxFit.contain,
      );
    } else if (resolved.isNotEmpty) {
      image = CachedForumImage(
        url: resolved,
        width: size.width - 32,
        height: size.height - 80,
        fit: BoxFit.contain,
      );
    } else {
      image = const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
      );
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
