import '../calls/call_message_display.dart';
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
      final existing = dialog.messages[idx];
      // Не затирать локальный cancelled/missed серверным talk duration:0
      // (бывает после ошибочного hangup до ответа).
      if (_shouldKeepLocalCallResult(existing, incoming)) {
        if (incoming.id.isNotEmpty &&
            !isLocalSkeleton(incoming) &&
            (existing.id.isEmpty || isLocalSkeleton(existing))) {
          existing.id = incoming.id;
        }
        return true;
      }
      MessageMapper.updateFromServer(existing, incoming);
      return true;
    }

    if (!_hasIdentity(incoming)) return false;
    dialog.messages.add(incoming);
    return true;
  }

  static bool _shouldKeepLocalCallResult(
    MessageViewModel existing,
    MessageViewModel incoming,
  ) {
    if (existing.type.toLowerCase() != 'call') return false;
    if (incoming.type.toLowerCase() != 'call') return false;
    final local = CallMessageBody.tryParse(existing.body);
    final remote = CallMessageBody.tryParse(incoming.body);
    if (local == null || remote == null) return false;
    if (local.callId.isEmpty ||
        remote.callId.isEmpty ||
        local.callId != remote.callId) {
      return false;
    }
    final localFailed =
        local.type == 'cancelled' || local.type == 'missed';
    final remoteTalkZero = remote.type == 'talk' && remote.duration <= 0;
    return localFailed && remoteTalkZero;
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

    // 3. Сообщения type=call: дедуп локального пузыря и серверного call_msg по call_id.
    final incomingCallId = _callIdOf(incoming);
    if (incomingCallId != null) {
      for (var i = 0; i < messages.length; i++) {
        if (_callIdOf(messages[i]) == incomingCallId) return i;
      }
    }

    return null;
  }

  static String? _callIdOf(MessageViewModel m) {
    if (m.type.toLowerCase() != 'call') return null;
    final id = CallMessageBody.tryParse(m.body)?.callId.trim() ?? '';
    return id.isEmpty ? null : id;
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
