import 'dart:convert';

import '../api/client_msg_hash.dart';
import '../api/msg_list_cursors.dart';
import '../models/media_file.dart';
import '../models/message_view_model.dart';

/// Формирование WS `msg` для пересылки (repost) без повторного upload.
class ForwardMapper {
  ForwardMapper._();

  static const _forwardTypes = {'txt', 'media', 'file', 'voice', 'geo', 'img', 'video'};

  static bool canForward(MessageViewModel message) {
    if (!MsgListCursors.isSavedMessage(message)) return false;
    return _forwardTypes.contains(serverType(message));
  }

  static String serverType(MessageViewModel message) {
    switch (message.type.toLowerCase()) {
      case 'text':
        return 'txt';
      case 'location':
      case 'geo':
        return 'geo';
      case 'image':
      case 'photo':
      case 'img':
        return 'img';
      case 'video':
        return 'video';
      case 'media':
      case 'file':
      case 'voice':
        return message.type.toLowerCase();
      default:
        if (message.isLocation) return 'geo';
        if (message.isVoice) return 'voice';
        if (message.isFile) return 'file';
        if (message.isImage) return 'media';
        return 'txt';
    }
  }

  static Map<String, dynamic> buildPayload({
    required MessageViewModel source,
    required String dlgId,
    required String hash,
    required String prnId,
  }) {
    final type = serverType(source);
    final payload = <String, dynamic>{
      'type': type,
      'hash': hash,
      'dlg_id': dlgId,
      'ai': 0,
      'repost': 1,
      'prn_id': prnId,
    };

    switch (type) {
      case 'txt':
        payload['body'] = _textBody(source);
      case 'media':
      case 'img':
      case 'video':
        payload['body'] = jsonEncode(_mediaBody(source));
        final files = _mediaFileEntries(source);
        if (files.isNotEmpty) payload['files'] = files;
      case 'file':
        payload['body'] = jsonEncode(_fileBody(source));
      case 'voice':
        payload['body'] = jsonEncode(_voiceBody(source));
        if (source.voiceHistogram.isNotEmpty) {
          payload['voice_histogram'] = source.voiceHistogram;
        }
        if (source.files.isNotEmpty) {
          payload['files'] = [_fileEntry(source.files.first)];
        }
      case 'geo':
        payload['body'] = jsonEncode(_geoBody(source));
        if (source.latitude != null) payload['lat'] = source.latitude;
        if (source.longitude != null) payload['lon'] = source.longitude;
        if ((source.address ?? '').trim().isNotEmpty) {
          payload['address'] = source.address!.trim();
        }
    }

    return payload;
  }

  static MessageViewModel buildSkeleton({
    required MessageViewModel source,
    required String hash,
    required String prnId,
    required String profileName,
    required String? profileId,
    required String nowIso,
    required String nowTime,
    required bool sameAuthorAsPrev,
  }) {
    final type = serverType(source);
    MediaFile? prnThumb;
    if (source.isImage && source.files.isNotEmpty) {
      prnThumb = source.files.first;
    }

    return MessageViewModel(
      id: hash,
      type: source.type,
      my: true,
      body: source.body,
      text: source.text,
      fr_name: profileName,
      fr_id: profileId,
      dttmcr: nowIso,
      dtshow: nowTime,
      status: -1,
      hash: hash,
      repost: true,
      prn_id: prnId,
      prn_fr_name: source.fr_name.trim().isNotEmpty ? source.fr_name.trim() : 'Сообщение',
      prn_fr_id: source.fr_id ?? '',
      prn_type: type == 'txt' ? 'txt' : type,
      prn_body: '',
      prn_fileTitle: source.fileTitle ?? '',
      prn_firstFile: prnThumb,
      fileTitle: source.fileTitle,
      fileSize: source.fileSize,
      fileFormat: source.fileFormat,
      desc: source.desc,
      files: List<MediaFile>.from(source.files),
      voiceHistogram: List<int>.from(source.voiceHistogram),
      size: source.size,
      latitude: source.latitude,
      longitude: source.longitude,
      address: source.address,
      showUserName: false,
      avaOnTop: !sameAuthorAsPrev,
      avaOnBottom: true,
    );
  }

  static String _textBody(MessageViewModel source) {
    final body = source.body.trim();
    if (body.isNotEmpty) return body;
    return source.text.trim();
  }

  static Map<String, dynamic> _mediaBody(MessageViewModel source) {
    return {
      'desc': source.desc.trim().isNotEmpty
          ? source.desc.trim()
          : (source.body.trim().isNotEmpty ? source.body.trim() : source.text.trim()),
      'files': _mediaFileEntries(source),
    };
  }

  static List<Map<String, String>> _mediaFileEntries(MessageViewModel source) {
    return source.files.map(_mediaFileEntry).toList();
  }

  static Map<String, String> _mediaFileEntry(MediaFile file) {
    return {
      if (file.hash.isNotEmpty) 'hash': file.hash,
      'kind': file.kind,
      'fname': file.fname,
      'fdir': file.fdir,
      'size': file.size.toString(),
      'width': file.width,
      'height': file.height,
      'duration': file.duration.toString(),
      if (file.preview.isNotEmpty) 'preview': file.preview,
    };
  }

  static Map<String, dynamic> _fileBody(MessageViewModel source) {
    final title = (source.fileTitle ?? '').trim().isNotEmpty
        ? source.fileTitle!.trim()
        : (source.files.isNotEmpty ? source.files.first.fname : 'Файл');
    return {
      'desc': source.desc.trim(),
      'title': title,
      'files': source.files
          .map(
            (f) => {
              'kind': f.kind,
              'title': f.title.isNotEmpty ? f.title : f.fname,
              'size': f.size.toString(),
              'fname': f.fname,
              'fdir': f.fdir,
              if (f.hash.isNotEmpty) 'hash': f.hash,
            },
          )
          .toList(),
    };
  }

  static Map<String, dynamic> _voiceBody(MessageViewModel source) {
    final file = source.files.isNotEmpty ? source.files.first : MediaFile();
    return {
      'kind': file.kind.isNotEmpty ? file.kind : 'mp3',
      'fname': file.fname,
      'fdir': file.fdir,
      if (file.hash.isNotEmpty) 'hash': file.hash,
      'duration': file.duration.toString(),
      'size': file.size.toString(),
      'hist': source.voiceHistogram,
      'desc': source.desc.trim(),
    };
  }

  static Map<String, dynamic> _geoBody(MessageViewModel source) {
    return {
      'lat': source.latitude ?? 0,
      'lon': source.longitude ?? 0,
      'adrs': source.address ?? '',
      'desc': source.desc.trim(),
    };
  }

  static Map<String, String> _fileEntry(MediaFile file) {
    return {
      if (file.hash.isNotEmpty) 'hash': file.hash,
      'kind': file.kind,
      'fname': file.fname,
      'fdir': file.fdir,
      'size': file.size.toString(),
    };
  }

  static String newHash() => ClientMsgHash.generate();
}
