import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_colors.dart';
import '../utils/media_message_layout.dart';
import 'media_thumb_tile.dart';

/// Альбом медиа в сообщении — раскладка как в iOS MediaMessageCell (1–10 файлов).
class MediaGrid extends StatelessWidget {
  final List<MediaFile> files;
  final double maxWidth;
  final bool albumLandscape;
  final void Function(MediaFile file)? onFileTap;

  const MediaGrid({
    super.key,
    required this.files,
    this.maxWidth = 280,
    this.albumLandscape = true,
    this.onFileTap,
  });

  /// Верхняя граница ширины альбома (как на iOS ~ширина пузыря, не весь экран).
  static const maxLayoutWidth = 400.0;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    final effectiveWidth = math
        .min(maxWidth, maxLayoutWidth)
        .clamp(120.0, maxLayoutWidth);
    final heightCap = math.min(
      MediaMessageLayout.maxPreviewHeight,
      effectiveWidth * 1.35,
    );

    final list = files.take(MediaMessageLayout.maxFiles).toList();
    final layout = MediaMessageLayout.compute(
      files: list,
      width: effectiveWidth,
      albumLandscape: albumLandscape,
      maxHeight: heightCap,
    );
    final single = list.length == 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: layout.totalWidth,
        height: layout.totalHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < list.length; i++)
              Positioned(
                left: layout.tiles[i].left,
                top: layout.tiles[i].top,
                width: layout.tiles[i].width,
                height: layout.tiles[i].height,
                child: ClipRect(
                  child: _tile(
                    list[i],
                    width: layout.tiles[i].width,
                    height: layout.tiles[i].height,
                    fit: single ? BoxFit.contain : BoxFit.cover,
                    playIconSize: layout.tiles[i].playIconSize,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    MediaFile file, {
    required double width,
    required double height,
    required BoxFit fit,
    required double playIconSize,
  }) {
    final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
    final hasUrl = file.url.isNotEmpty;

    Widget content;

    if (hasBytes) {
      content = Image.memory(
        file.bytes!,
        key: ValueKey('${file.hash}_${width.round()}x${height.round()}'),
        fit: fit,
        width: width,
        height: height,
      );
    } else if (hasUrl || MediaThumbCache.needsRemoteThumbnail(file)) {
      content = MediaThumbTile(
        key: ValueKey('${file.hash}_${width.round()}x${height.round()}'),
        file: file,
        width: width,
        height: height,
        fit: fit,
      );
    } else {
      final gradient = AppColors.avatarGradientFor(
        file.hash.isNotEmpty ? file.hash : '${file.width}x${file.height}',
      );
      content = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Colors.white54, size: 40),
      );
    }

    content = SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          _overlay(file, playIconSize: playIconSize),
        ],
      ),
    );

    if (onFileTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onFileTap!(file),
      child: content,
    );
  }

  Widget _overlay(
    MediaFile file, {
    required double playIconSize,
  }) {
    if (!file.isVideo) return const SizedBox.shrink();

    return Stack(
      children: [
        Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Colors.white.withValues(alpha: 0.92),
            size: playIconSize,
          ),
        ),
        if (file.duration > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatDuration(file.duration),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
