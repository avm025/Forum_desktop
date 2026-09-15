import '../models/message_view_model.dart';

/// Результат msg_list (WS_MSG_LIST.md).
class MsgListResult {
  /// Размер страницы истории на сервере.
  static const int historyPageSize = 100;

  final List<MessageViewModel> messages;

  /// `msg_id` непрочитанных упоминаний текущего пользователя (`msgs_usr`).
  final List<String> msgsUsr;

  /// В ответе есть data.first_id → режим истории (вставка в начало).
  final bool isHistory;

  /// first_id из ответа сервера (курсор / маркер истории).
  final String? responseFirstId;

  /// Ещё есть старая история (history && msgs.length >= 100).
  final bool hasMoreHistory;

  const MsgListResult({
    required this.messages,
    this.msgsUsr = const [],
    this.isHistory = false,
    this.responseFirstId,
    this.hasMoreHistory = false,
  });

  static const empty = MsgListResult(messages: []);
}
