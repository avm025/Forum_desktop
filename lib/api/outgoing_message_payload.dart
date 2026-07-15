import 'dart:convert';

import '../models/media_file.dart';
import '../models/message_view_model.dart';
import '../utils/emoticon_replacer.dart';
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
  static Map<String, dynamic>? build({
    required MessageViewModel message,
    required String dlgId,
  }) {
    if (message.repost && message.prn_id.trim().isNotEmpty) {
      return ForwardMapper.buildPayload(
        source: message,
        dlgId: dlgId,
        hash: _hash(message),
        prnId: message.prn_id.trim(),
      );
    }

    switch (_serverType(message)) {
      case 'txt':
        return _text(message, dlgId);
      case 'media':
        if (!_filesReady(message.files)) return null;
        return _media(message, dlgId);
      case 'file':
        if (!_filesReady(message.files)) return null;
        return _file(message, dlgId);
      default:
        return null;
    }
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

  static Map<String, dynamic> _text(MessageViewModel message, String dlgId) {
    final body = EmoticonReplacer.replace(
      (message.body.trim().isNotEmpty ? message.body : message.text).trim(),
    );
    final payload = <String, dynamic>{
      'type': 'txt',
      'hash': _hash(message),
      'dlg_id': dlgId,
      'ai': message.ai,
      'body': body,
    };
    final prnId = message.prn_id.trim();
    if (prnId.isNotEmpty) payload['prn_id'] = prnId;
    return payload;
  }

  static Map<String, dynamic> _media(MessageViewModel message, String dlgId) {
    final cap = EmoticonReplacer.replace(
      (message.desc.trim().isNotEmpty
              ? message.desc
              : (message.body.trim().isNotEmpty ? message.body : message.text))
          .trim(),
    );
    return {
      'type': 'media',
      'hash': _hash(message),
      'dlg_id': dlgId,
      'ai': message.ai,
      'body': jsonEncode({
        'desc': cap,
        'files': message.files.map(_mediaFileEntry).toList(),
      }),
    };
  }

  static Map<String, dynamic> _file(MessageViewModel message, String dlgId) {
    return {
      'type': 'file',
      'hash': _hash(message),
      'dlg_id': dlgId,
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
                title: f.title.isNotEmpty ? f.title : f.fname,
              ),
            )
            .toList(),
      }),
    };
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
