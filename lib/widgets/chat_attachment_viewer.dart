import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../utils/attachment_kind.dart';
import '../utils/file_opener.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';
import '../utils/media_viewer_context.dart';
import 'fullscreen_document_viewer.dart';
import 'fullscreen_image_view.dart';
import 'fullscreen_video_viewer.dart';
import 'telegram_media_loader.dart';
import 'telegram_media_overlay.dart';

/// Открытие вложений прямо в чате (фото, видео, PDF, текст).
class ChatAttachmentViewer {
  ChatAttachmentViewer._();

  static Future<void> show(
    BuildContext context,
    MediaFile file, {
    MediaViewerContext? viewerContext,
    Future<void> Function(String action)? onOverlayAction,
  }) async {
    switch (AttachmentKind.of(file)) {
      case AttachmentViewKind.image:
        await FullscreenImageViewer.show(
          context,
          file,
          viewerContext: viewerContext,
          onOverlayAction: onOverlayAction,
        );
      case AttachmentViewKind.video:
        await FullscreenVideoViewer.show(
          context,
          file,
          viewerContext: viewerContext,
          onOverlayAction: onOverlayAction,
        );
      case AttachmentViewKind.pdf:
      case AttachmentViewKind.text:
        await FullscreenDocumentViewer.show(
          context,
          file,
          viewerContext: viewerContext,
          onOverlayAction: onOverlayAction,
        );
      case AttachmentViewKind.other:
        await _openOtherWithLoader(context, file);
    }
  }

  /// Скачивание крупного файла с круговым прогрессом, затем системный open.
  static Future<void> _openOtherWithLoader(
    BuildContext context,
    MediaFile file,
  ) async {
    final already = await MediaFileLoader.isDownloaded(
      file,
      downloadUrl: MediaFileUrl.resolve(file),
    );
    if (already) {
      final ok = await FileOpener.open(file);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть файл')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    // Лоадер «другого» файла — без разворота на весь монитор.
    await TelegramMediaOverlay.show(
      context: context,
      coverDisplay: false,
      builder: (ctx) => _OpeningFileDialog(file: file),
    );
  }
}

class _OpeningFileDialog extends StatefulWidget {
  final MediaFile file;

  const _OpeningFileDialog({required this.file});

  @override
  State<_OpeningFileDialog> createState() => _OpeningFileDialogState();
}

class _OpeningFileDialogState extends State<_OpeningFileDialog> {
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final url = MediaFileUrl.resolve(widget.file);
      await MediaFileLoader.ensureCached(
        widget.file,
        downloadUrl: url,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      // Подставляем локальный путь, чтобы FileOpener не качал снова.
      final path = await MediaFileLoader.cachedPathIfExists(
        widget.file,
        downloadUrl: url,
      );
      if (path != null) {
        widget.file.URL = path;
      }
      final ok = await FileOpener.open(widget.file);
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = 'Не удалось открыть файл');
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return TelegramMediaOverlayShell(
      showCloseButton: _error != null,
      child: TelegramMediaCard(
        maxWidth: 300,
        maxHeight: 220,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error == null)
                TelegramMediaLoadingOverlay(progress: _progress)
              else
                const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Загрузка файла…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
