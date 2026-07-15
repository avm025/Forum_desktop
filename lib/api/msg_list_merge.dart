import '../models/dialogs_list_view_model.dart';
import '../models/message_view_model.dart';
import 'message_mapper.dart';
import 'msg_list_cursors.dart';
import 'msg_list_result.dart';

/// Слияние ответа msg_list в список сообщений диалога.
class MsgListMerge {
  MsgListMerge._();

  static void apply({
    required DialogsListViewModel dialog,
    required MsgListResult result,
    required void Function(bool hasMoreHistory) onHistoryPagination,
  }) {
    if (result.messages.isEmpty) {
      if (result.isHistory) onHistoryPagination(false);
      return;
    }

    if (result.isHistory) {
      _prependHistory(dialog, result.messages);
      onHistoryPagination(result.hasMoreHistory);
    } else {
      _appendNewer(dialog, result.messages);
    }

    MessageMapper.applyGrouping(
      dialog.messages,
      isGroupChat: dialog.isGrp,
    );
  }

  /// Одно push-сообщение `type: msg`.
  /// Сначала поиск по [id], для локальных скелетов — по [hash].
  static bool applyIncoming({
    required DialogsListViewModel dialog,
    required MessageViewModel incoming,
  }) {
    final idx = _findMatchIndex(dialog.messages, incoming);
    if (idx != null) {
      MessageMapper.updateFromServer(dialog.messages[idx], incoming);
      return true;
    }

    if (!_hasIdentity(incoming)) return false;
    dialog.messages.add(incoming);
    return true;
  }

  static bool _hasIdentity(MessageViewModel m) {
    return m.id.isNotEmpty || m.hash.isNotEmpty;
  }

  /// Локальный скелет до эха сервера: id совпадает с клиентским hash.
  static bool isLocalSkeleton(MessageViewModel m) {
    if (m.id.isEmpty || m.hash.isEmpty) return false;
    if (m.id != m.hash) return false;
    return !MsgListCursors.isSavedMessage(m);
  }

  static int? _findMatchIndex(
    List<MessageViewModel> messages,
    MessageViewModel incoming,
  ) {
    final incomingId = incoming.id.trim();
    final incomingHash = incoming.hash.trim();

    // 1. Поиск по серверному id.
    if (incomingId.isNotEmpty && !isLocalSkeleton(incoming)) {
      for (var i = 0; i < messages.length; i++) {
        if (messages[i].id == incomingId) return i;
      }
    }

    // 2. Поиск по hash (эхо только что отправленного скелета).
    final hashKeys = <String>{};
    if (incomingHash.isNotEmpty) hashKeys.add(incomingHash);
    if (isLocalSkeleton(incoming)) hashKeys.add(incomingId);

    for (final key in hashKeys) {
      for (var i = 0; i < messages.length; i++) {
        final existing = messages[i];
        if (existing.hash == key) return i;
        if (existing.id == key) return i;
      }
    }

    return null;
  }

  static void _prependHistory(
    DialogsListViewModel dialog,
    List<MessageViewModel> incoming,
  ) {
    if (dialog.messages.isEmpty) {
      dialog.messages = List.of(incoming);
      return;
    }

    final older = <MessageViewModel>[];
    for (final m in incoming) {
      if (!_hasIdentity(m)) continue;
      if (_findMatchIndex(dialog.messages, m) != null) continue;
      older.add(m);
    }
    if (older.isEmpty) return;
    dialog.messages = [...older, ...dialog.messages];
  }

  static void _appendNewer(
    DialogsListViewModel dialog,
    List<MessageViewModel> incoming,
  ) {
    if (dialog.messages.isEmpty) {
      dialog.messages = List.of(incoming);
      return;
    }

    for (final m in incoming) {
      if (!_hasIdentity(m)) continue;
      applyIncoming(dialog: dialog, incoming: m);
    }
  }
}
