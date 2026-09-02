import 'dart:convert';

import '../models/dialogs_list_view_model.dart';
import '../models/media_file.dart';
import '../models/message_view_model.dart';
import '../utils/emoticon_replacer.dart';
import '../utils/media_display_name.dart';
import 'forward_mapper.dart';
import 'msg_list_cursors.dart';
import 'msg_list_merge.dart';
import 'uploaded_file_info.dart';

/// Сборка WS `msg` для повторной отправки локального скелета.
class OutgoingMessagePayload {
  OutgoingMessagePayload._();

  static bool isPending(MessageViewModel message) {
    if (!message.my || message.status != -1) return false;
    if (message.hash.trim().isEmpty) return false;
    return MsgListMerge.isLocalSkeleton(message) ||
        !MsgListCursors.isSavedMessage(message);
  }

  /// Синхронная сборка payload, если не нужен повторный upload.
  ///
  /// При [toId] (новый контакт, `dlg_id == "0"`) поле `dlg_id` не кладётся.
  static Map<String, dynamic>? build({
    required MessageViewModel message,
    required String dlgId,
    String? toId,
  }) {
    if (message.repost && message.prn_id.trim().isNotEmpty) {
      // Репост в новый контакт не поддерживаем — нужен реальный dlg_id.
      if (toId != null && toId.trim().isNotEmpty) return null;
      return ForwardMapper.buildPayload(
        source: message,
        dlgId: dlgId,
        hash: _hash(message),
        prnId: message.prn_id.trim(),
      );
    }

    switch (_serverType(message)) {
      case 'txt':
        return _text(message, dlgId: dlgId, toId: toId);
      case 'media':
        if (!_filesReady(message.files)) return null;
        return _media(message, dlgId: dlgId, toId: toId);
      case 'file':
        if (!_filesReady(message.files)) return null;
        return _file(message, dlgId: dlgId, toId: toId);
      default:
        return null;
    }
  }

  static Map<String, dynamic>? buildForDialog({
    required MessageViewModel message,
    required DialogsListViewModel dialog,
  }) {
    if (dialog.isNewContactWithoutDialog) {
      final toId = dialog.usr_id?.trim() ?? '';
      if (toId.isEmpty) return null;
      return build(message: message, dlgId: '', toId: toId);
    }
    final dlgId = dialog.id?.trim() ?? '';
    if (dlgId.isEmpty || DialogsListViewModel.isPlaceholderDlgId(dlgId)) {
      return null;
    }
    return build(message: message, dlgId: dlgId);
  }

  static bool needsUpload(MessageViewModel message) {
    if (message.repost) return false;
    final type = _serverType(message);
    if (type != 'media' && type != 'file') return false;
    return !_filesReady(message.files);
  }

  static String _hash(MessageViewModel message) {
    final hash = message.hash.trim();
    if (hash.isNotEmpty) return hash;
    return message.id.trim();
  }

  static String _serverType(MessageViewModel message) {
    if (message.repost) return ForwardMapper.serverType(message);
    switch (message.type.toLowerCase()) {
      case 'text':
      case 'txt':
        return 'txt';
      case 'media':
      case 'image':
      case 'photo':
      case 'img':
      case 'video':
        return 'media';
      case 'file':
        return 'file';
      default:
        if (message.isImage) return 'media';
        if (message.isFile) return 'file';
        return 'txt';
    }
  }

  static void _applyTarget(
    Map<String, dynamic> payload, {
    required String dlgId,
    String? toId,
  }) {
    final tid = toId?.trim() ?? '';
    if (tid.isNotEmpty) {
      payload['to_id'] = tid;
      return;
    }
    payload['dlg_id'] = dlgId;
  }

  static Map<String, dynamic> _text(
    MessageViewModel message, {
    required String dlgId,
    String? toId,
  }) {
    final body = EmoticonReplacer.replace(
      (message.body.trim().isNotEmpty ? message.body : message.text).trim(),
    );
    final payload = <String, dynamic>{
      'type': 'txt',
      'hash': _hash(message),
      'ai': message.ai,
      'body': body,
    };
    _applyTarget(payload, dlgId: dlgId, toId: toId);
    final prnId = message.prn_id.trim();
    if (prnId.isNotEmpty) payload['prn_id'] = prnId;
    return payload;
  }

  static Map<String, dynamic> _media(
    MessageViewModel message, {
    required String dlgId,
    String? toId,
  }) {
    final cap = EmoticonReplacer.replace(
      (message.desc.trim().isNotEmpty
              ? message.desc
              : (message.body.trim().isNotEmpty ? message.body : message.text))
          .trim(),
    );
    final payload = <String, dynamic>{
      'type': 'media',
      'hash': _hash(message),
      'ai': message.ai,
      'body': jsonEncode({
        'desc': cap,
        'files': message.files.map(_mediaFileEntry).toList(),
      }),
    };
    _applyTarget(payload, dlgId: dlgId, toId: toId);
    return payload;
  }

  static Map<String, dynamic> _file(
    MessageViewModel message, {
    required String dlgId,
    String? toId,
  }) {
    final payload = <String, dynamic>{
      'type': 'file',
      'hash': _hash(message),
      'ai': message.ai,
      'body': jsonEncode({
        'desc': message.desc.trim(),
        'files': message.files
            .map(
              (f) => UploadedFileInfo(
                hash: f.hash,
                fname: f.fname,
                fdir: f.fdir,
                kind: f.kind,
                size: f.size,
              ).toDocumentFileJson(
                title: MediaDisplayName.forFile(f, dttmcr: message.dttmcr),
              ),
            )
            .toList(),
      }),
    };
    _applyTarget(payload, dlgId: dlgId, toId: toId);
    return payload;
  }

  static Map<String, String> _mediaFileEntry(MediaFile file) {
    return UploadedFileInfo(
      hash: file.hash,
      fname: file.fname,
      fdir: file.fdir,
      kind: file.kind,
      size: file.size,
    ).toMediaFileJson(
      width: file.width,
      height: file.height,
      duration: file.duration.toString(),
      preview: file.preview,
    );
  }

  static bool _filesReady(List<MediaFile> files) {
    if (files.isEmpty) return false;
    return files.every(
      (f) =>
          f.hash.trim().isNotEmpty &&
          f.fdir.trim().isNotEmpty &&
          f.fname.trim().isNotEmpty,
    );
  }
}
