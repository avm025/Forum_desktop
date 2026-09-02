import '../models/media_file.dart';
import '../models/message_view_model.dart';

/// Поиск по тексту сообщений в открытом диалоге (клиентская фильтрация).
class ChatMessageSearch {
  ChatMessageSearch._();

  static bool _isAttachmentPayloadJson(String value) {
    final t = value.trimLeft();
    if (!t.startsWith('{')) return false;
    return t.contains('"files"') ||
        t.contains('"fname"') ||
        t.contains('"fdir"') ||
        (t.contains('"desc"') && t.contains('"kind"'));
  }

  static void _addPart(List<String> parts, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || _isAttachmentPayloadJson(value)) return;
    parts.add(value);
  }

  /// Собирает все пользовательские строки сообщения для поиска.
  static String searchableText(MessageViewModel message) {
    final parts = <String>[];

    _addPart(parts, message.body);
    _addPart(parts, message.text);
    _addPart(parts, message.desc);
    _addPart(parts, message.fileTitle);
    _addPart(parts, message.fr_name);

    for (final MediaFile file in message.files) {
      _addPart(parts, file.title);
      _addPart(parts, file.fname);
    }

    if (message.isLocation) {
      _addPart(parts, message.address);
    }

    if (message.isCall) {
      _addPart(parts, message.desc);
    }

    return parts.join(' ');
  }

  /// Id совпадений в порядке ленты (от старых к новым).
  static List<String> matchIds(
    List<MessageViewModel> messages,
    String query, {
    required String Function(MessageViewModel message) stableId,
  }) {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final lower = q.toLowerCase();
    final result = <String>[];
    for (final message in messages) {
      if (searchableText(message).toLowerCase().contains(lower)) {
        result.add(stableId(message));
      }
    }
    return result;
  }

  /// Разбивает [text] на [TextSpan]-совместимые фрагменты с подсветкой.
  static List<({String text, bool match})> highlightParts(
    String text,
    String query,
  ) {
    final q = query.trim();
    if (q.isEmpty) return [(text: text, match: false)];

    final lowerText = text.toLowerCase();
    final lowerQuery = q.toLowerCase();
    final parts = <({String text, bool match})>[];
    var start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        parts.add((text: text.substring(start), match: false));
        break;
      }
      if (index > start) {
        parts.add((text: text.substring(start, index), match: false));
      }
      parts.add((
        text: text.substring(index, index + q.length),
        match: true,
      ));
      start = index + q.length;
    }

    return parts;
  }
}
