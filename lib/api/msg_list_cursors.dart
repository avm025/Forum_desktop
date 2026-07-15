import '../models/message_view_model.dart';

/// Курсоры пагинации msg_list (setLastFirstMessage).
class MsgListCursors {
  MsgListCursors._();

  static const _hex40 = r'^[0-9a-fA-F]{40}$';

  /// Сообщение участвует в курсорах (не date, не локальный скелет).
  static bool isSavedMessage(MessageViewModel m) {
    if (m.type == 'date') return false;
    if (m.id.isEmpty) return false;
    if (m.hash.isNotEmpty && m.id == m.hash && RegExp(_hex40).hasMatch(m.id)) {
      return false;
    }
    return true;
  }

  static MessageViewModel? firstSaved(List<MessageViewModel> messages) {
    for (final m in messages) {
      if (isSavedMessage(m)) return m;
    }
    return null;
  }

  static MessageViewModel? lastSaved(List<MessageViewModel> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (isSavedMessage(messages[i])) return messages[i];
    }
    return null;
  }

  /// ISO 8601 — max(dttmcr, dttmup) последнего сообщения.
  static String lastDt(MessageViewModel m) {
    final cr = m.dttmcr.trim();
    final up = m.dttmup.trim();
    if (cr.isEmpty) return up;
    if (up.isEmpty) return cr;
    return cr.compareTo(up) >= 0 ? cr : up;
  }
}
