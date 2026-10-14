import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../utils/media_file_url.dart';
import '../utils/media_viewer_context.dart';
import '../utils/native_media_overlay.dart';
import 'cached_forum_image.dart';
import 'telegram_media_loader.dart';
import 'telegram_media_overlay.dart';

/// Просмотр фото на размытом фоне (как в Telegram).
class FullscreenImageViewer extends StatelessWidget {
  final MediaFile file;
  final MediaViewerContext? viewerContext;

  const FullscreenImageViewer({
    super.key,
    required this.file,
    this.viewerContext,
  });

  static Future<void> show(
    BuildContext context,
    MediaFile file, {
    MediaViewerContext? viewerContext,
    Future<void> Function(String action)? onOverlayAction,
  }) async {
    if (await NativeMediaOverlay.showFile(
      file,
      context: viewerContext,
      onAction: onOverlayAction,
    )) {
      return;
    }
    if (!context.mounted) return;
    await TelegramMediaOverlay.show(
      context: context,
      builder: (_) => FullscreenImageViewer(
        file: file,
        viewerContext: viewerContext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width - 48;
    final maxH = size.height - 100;
    final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
    final preview = file.preview.trim();
    final resolved = MediaFileUrl.resolve(file);
    final localPath = file.URL?.trim() ?? '';
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

    Widget loading = SizedBox(
      width: maxW.clamp(160, 480),
      height: maxH.clamp(160, 480),
      child: TelegramMediaLoadingStack(
        background: thumbPlaceholder,
        progress: null,
      ),
    );

    Widget image;
    if (hasBytes) {
      image = Image.memory(
        file.bytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync || frame != null) return child;
          return loading;
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
          return loading;
        },
      );
    } else if (networkUrl.isNotEmpty) {
      image = CachedForumImage(
        url: networkUrl,
        width: maxW,
        height: maxH,
        fit: BoxFit.contain,
        blankWhileLoading: true,
        telegramLoader: true,
        placeholder: thumbPlaceholder,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
      );
    } else if (thumbPlaceholder != null) {
      image = thumbPlaceholder;
    } else {
      image = loading;
    }

    return TelegramMediaOverlayShell(
      showCloseButton: false,
      viewerContext: viewerContext,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: image,
        ),
      ),
    );
  }
}
