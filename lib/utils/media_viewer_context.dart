import 'package:intl/intl.dart';

import '../models/message_view_model.dart';
import 'message_text_format.dart';

/// Контекст просмотра медиа (подпись, чат, дата) — как в Telegram.
class MediaViewerContext {
  /// Текст сообщения / caption (без markdown-маркеров).
  final String caption;

  /// Название чата или канала.
  final String chatTitle;

  /// «сегодня 14:32» / «вчера 14:32» / «12.03.2026 14:32».
  final String dateLabel;

  final String messageId;
  final String dialogId;

  const MediaViewerContext({
    this.caption = '',
    this.chatTitle = '',
    this.dateLabel = '',
    this.messageId = '',
    this.dialogId = '',
  });

  bool get hasChrome =>
      caption.trim().isNotEmpty ||
      chatTitle.trim().isNotEmpty ||
      dateLabel.trim().isNotEmpty;

  static MediaViewerContext fromMessage({
    required MessageViewModel message,
    required String chatTitle,
    String? captionRaw,
    String dialogId = '',
  }) {
    final raw = (captionRaw ?? _captionOf(message)).trim();
    return MediaViewerContext(
      caption: MessageTextFormat.plain(raw).trim(),
      chatTitle: chatTitle.trim(),
      dateLabel: formatDateTime(
        message.dttmcr.isNotEmpty ? message.dttmcr : message.dttmup,
      ),
      messageId: message.id.trim(),
      dialogId: dialogId.trim(),
    );
  }

  static String _captionOf(MessageViewModel message) {
    if (message.isFile || (message.isImage && message.hasFiles)) {
      final caption = message.desc.trim();
      if (caption.isNotEmpty) return caption;
      final body = message.body.trim();
      if (body.isNotEmpty && !_isAttachmentPayloadJson(body)) return body;
      return '';
    }
    return message.body.isNotEmpty ? message.body : message.text;
  }

  static bool _isAttachmentPayloadJson(String value) {
    final t = value.trimLeft();
    if (!t.startsWith('{')) return false;
    return t.contains('"files"') ||
        t.contains('"fname"') ||
        t.contains('"fdir"') ||
        (t.contains('"desc"') && t.contains('"kind"'));
  }

  static String formatDateTime(String iso) {
    if (iso.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final time = DateFormat('HH:mm').format(dt);
      if (msgDay == today) return 'сегодня $time';
      if (msgDay == today.subtract(const Duration(days: 1))) {
        return 'вчера $time';
      }
      return '${DateFormat('dd.MM.yyyy').format(dt)} $time';
    } catch (_) {
      return iso.trim();
    }
  }
}
