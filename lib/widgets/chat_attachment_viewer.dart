import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../utils/attachment_kind.dart';
import '../utils/file_opener.dart';
import 'fullscreen_document_viewer.dart';
import 'fullscreen_image_view.dart';
import 'fullscreen_video_viewer.dart';

/// Открытие вложений прямо в чате (фото, видео, PDF, текст).
class ChatAttachmentViewer {
  ChatAttachmentViewer._();

  static Future<void> show(BuildContext context, MediaFile file) async {
    switch (AttachmentKind.of(file)) {
      case AttachmentViewKind.image:
        await FullscreenImageViewer.show(context, file);
      case AttachmentViewKind.video:
        await FullscreenVideoViewer.show(context, file);
      case AttachmentViewKind.pdf:
      case AttachmentViewKind.text:
        await FullscreenDocumentViewer.show(context, file);
      case AttachmentViewKind.other:
        final ok = await FileOpener.open(file);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть файл')),
          );
        }
    }
  }
}
