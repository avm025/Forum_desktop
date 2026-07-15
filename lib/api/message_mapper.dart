import 'dart:convert';

import 'package:intl/intl.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../models/message_emoji_model.dart';
import '../api/likes_mapper.dart';
import '../models/message_view_model.dart';
/// Преобразование сообщений с сервера (msg_list / msg) → [MessageViewModel].
class MessageMapper {
  MessageMapper._();

  /// Список сообщений из ответа msg_list с группировкой аватаров.
  static List<MessageViewModel> fromMsgList(
    List<dynamic> raw, {
    String? currentUserId,
    bool isGroupChat = false,
  }) {
    final messages = raw
        .whereType<Map>()
        .map((e) => fromServerJson(
              Map<String, dynamic>.from(e),
              currentUserId: currentUserId,
            ))
        .toList();

    applyGrouping(messages, isGroupChat: isGroupChat);
    return messages;
  }

  /// Пересчитать группировку аватаров/имён после слияния страниц.
  static void applyGrouping(
    List<MessageViewModel> messages, {
    required bool isGroupChat,
  }) {
    _applyGrouping(messages, isGroupChat: isGroupChat);
  }

  static MessageViewModel fromServerJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final serverType = json['type']?.toString() ?? 'txt';
    final uiType = _mapType(serverType);
    final frId = json['fr_id']?.toString() ?? '';
    final my = currentUserId != null &&
        currentUserId.isNotEmpty &&
        frId == currentUserId;

    final bodyRaw = json['body']?.toString() ?? '';
    final bodyJson = _tryParseJson(bodyRaw);

    var body = bodyRaw;
    var text = bodyRaw;
    var desc = '';
    var files = <MediaFile>[];
    var voiceHistogram = <int>[];
    String? fileTitle;
    String? fileSize;
    String? fileFormat;
    double? lat;
    double? lon;
    String? address;
    MsgSize size = MsgSize.zero;

    switch (serverType) {
      case 'txt':
        body = bodyRaw;
        text = bodyRaw;
      case 'media':
      case 'img':
      case 'video':
        desc = bodyJson?['desc']?.toString() ?? '';
        body = desc;
        text = desc;
        files = _parseFiles(bodyJson?['files'] ?? json['files']);
        if (files.isNotEmpty) {
          size = MsgSize(files.first.widthValue, files.first.heightValue);
        }
      case 'file':
        desc = bodyJson?['desc']?.toString() ?? bodyJson?['title']?.toString() ?? '';
        body = desc;
        files = _parseFiles(bodyJson?['files']);
        if (files.isEmpty && bodyJson != null) {
          files = [_fileFromMap(bodyJson)];
        }
        if (files.isNotEmpty) {
          fileTitle = files.first.fname.isNotEmpty
              ? (bodyJson?['title']?.toString() ?? files.first.fname)
              : bodyJson?['title']?.toString();
          fileSize = files.first.humanSize;
          fileFormat = files.first.formatLabel;
        }
      case 'voice':
        final voiceBody = bodyJson ?? json;
        files = [_fileFromMap(voiceBody)];
        voiceHistogram = _parseHistogram(
          voiceBody['hist'] ?? voiceBody['voice_histogram'] ?? json['voice_histogram'],
        );
        desc = voiceBody['desc']?.toString() ?? '';
        body = 'Голосовое сообщение';
      case 'geo':
        final geo = bodyJson ?? json;
        lat = _toDouble(geo['lat'] ?? geo['latitude']);
        lon = _toDouble(geo['lon'] ?? geo['longitude']);
        address = geo['adrs']?.toString() ?? geo['address']?.toString() ?? '';
        desc = geo['desc']?.toString() ?? '';
        body = address.isNotEmpty ? address : 'Геопозиция';
      default:
        if (bodyJson != null) {
          desc = bodyJson['desc']?.toString() ?? '';
          body = desc.isNotEmpty ? desc : bodyRaw;
        }
    }

    final prnBody = json['prn_body']?.toString() ?? '';
    final prnBodyJson = _tryParseJson(prnBody);
    MediaFile? prnFirstFile;
    if (prnBodyJson != null) {
      final prnFiles = _parseFiles(prnBodyJson['files']);
      if (prnFiles.isNotEmpty) prnFirstFile = prnFiles.first;
    }

    return MessageViewModel(
      id: json['id']?.toString() ?? json['hash']?.toString() ?? '',
      type: uiType,
      ai: _parseInt(json['ai']),
      my: my,
      body: body,
      text: text,
      fr_name: json['fr_name']?.toString() ?? '',
      fr_id: frId.isEmpty ? null : frId,
      dttmcr: json['dttmcr']?.toString() ?? '',
      dttmup: json['dttmup']?.toString() ?? '',
      dttmrd: json['dttmrd']?.toString() ?? '',
      dtshow: _formatTime(json['dttmcr']?.toString() ?? ''),
      status: _parseInt(json['status']),
      preview: json['preview']?.toString() ?? '',
      url: ApiConfig.mediaUrl(json['url']?.toString()),
      fdir: json['fdir']?.toString() ?? '',
      hash: json['hash']?.toString() ?? '',
      prn_id: _normalizePrnId(json['prn_id']),
      prn_body: prnBodyJson?['desc']?.toString() ??
          prnBodyJson?['body']?.toString() ??
          prnBody,
      prn_fr_id: json['prn_fr_id']?.toString() ?? '',
      prn_fr_name: json['prn_fr_name']?.toString() ?? '',
      prn_type: json['prn_type']?.toString() ?? '',
      prn_fileTitle: prnBodyJson?['title']?.toString() ?? '',
      prn_firstFile: prnFirstFile,
      repost: _parseRepost(json['repost']),
      fileTitle: fileTitle,
      fileSize: fileSize,
      fileFormat: fileFormat,
      desc: desc,
      files: files,
      voiceHistogram: voiceHistogram,
      size: size,
      latitude: lat,
      longitude: lon,
      address: address,
      emoji: LikesMapper.parseList(json['likes'], currentUserId: currentUserId),
    );
  }

  /// Обновить существующее сообщение данными с сервера (push msg / эхо).
  static void updateFromServer(MessageViewModel target, MessageViewModel incoming) {
    if (incoming.id.isNotEmpty) target.id = incoming.id;
    target.body = incoming.body;
    target.text = incoming.text;
    target.dttmcr = incoming.dttmcr;
    target.dttmup = incoming.dttmup;
    target.dttmrd = incoming.dttmrd;
    target.dtshow = incoming.dtshow;
    target.status = incoming.status;
    target.preview = incoming.preview;
    target.url = incoming.url;
    target.fdir = incoming.fdir;
    if (incoming.hash.isNotEmpty) target.hash = incoming.hash;
    target.desc = incoming.desc;
    target.fileTitle = incoming.fileTitle;
    if (incoming.files.isNotEmpty) {
      target.files = List.of(incoming.files);
    }
    if (incoming.voiceHistogram.isNotEmpty) {
      target.voiceHistogram = List.of(incoming.voiceHistogram);
    }
    target.emoji = List<MessageEmojiModel>.from(incoming.emoji);
    target.latitude = incoming.latitude;
    target.longitude = incoming.longitude;
    target.address = incoming.address;
    target.repost = incoming.repost;
    target.prn_id = incoming.prn_id;
    target.prn_body = incoming.prn_body;
    target.prn_fr_id = incoming.prn_fr_id;
    target.prn_fr_name = incoming.prn_fr_name;
    target.prn_type = incoming.prn_type;
    target.prn_fileTitle = incoming.prn_fileTitle;
    target.prn_firstFile = incoming.prn_firstFile;
  }

  /// Заменить реакции сообщения (push `add_like`).
  static void updateLikes(
    MessageViewModel target,
    List<MessageEmojiModel> likes,
  ) {
    target.emoji = List<MessageEmojiModel>.from(likes);
  }

  static void _applyGrouping(List<MessageViewModel> messages,
      {required bool isGroupChat}) {
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final next = i < messages.length - 1 ? messages[i + 1] : null;

      final sameAsPrev = prev != null && prev.fr_id == m.fr_id;
      final sameAsNext = next != null && next.fr_id == m.fr_id;

      if (isGroupChat && !m.my) {
        m.showUserName = !sameAsPrev;
      }
      // Кластер одного отправителя (скругления пузыря, отступы).
      m.avaOnTop = !sameAsPrev;
      m.avaOnBottom = !sameAsNext;
    }
  }

  static String _mapType(String serverType) {
    switch (serverType) {
      case 'txt':
        return 'text';
      case 'geo':
        return 'location';
      case 'img':
        return 'image';
      case 'media':
      case 'video':
        return 'media';
      default:
        return serverType;
    }
  }

  static List<MediaFile> _parseFiles(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(_fileFromMap).toList();
  }

  static MediaFile _fileFromMap(Map<dynamic, dynamic> map) {
    final m = Map<String, dynamic>.from(map);
    final fdir = m['fdir']?.toString() ?? '';
    final fname = m['fname']?.toString() ?? '';
    final title = m['title']?.toString() ?? '';
    final name = fname.isNotEmpty ? fname : title;
    return MediaFile(
      hash: m['hash']?.toString() ?? '',
      url: m['url']?.toString().isNotEmpty == true
          ? ApiConfig.mediaUrl(m['url']?.toString())
          : ApiConfig.fileUrl(fdir, name),
      fname: name,
      fdir: fdir,
      kind: m['kind']?.toString() ?? m['type']?.toString() ?? '',
      preview: ApiConfig.mediaUrl(m['preview']?.toString()),
      title: title,
      size: _parseInt(m['size']),
      width: m['width']?.toString() ?? '0',
      height: m['height']?.toString() ?? '0',
      duration: _parseInt(m['duration']),
      uploaded: true,
    );
  }

  static List<int> _parseHistogram(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => _parseInt(e)).toList();
  }

  static Map<String, dynamic>? _tryParseJson(String raw) {
    if (raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static String _normalizePrnId(dynamic value) {
    final s = value?.toString().trim() ?? '';
    if (s.isEmpty || s == '0' || s == 'null') return '';
    return s;
  }

  static bool _parseRepost(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    final s = value?.toString().trim().toLowerCase();
    return s == '1' || s == 'true';
  }

  static String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      if (msgDay == today) return DateFormat('HH:mm').format(dt);
      if (msgDay == today.subtract(const Duration(days: 1))) return 'вчера';
      return DateFormat('dd.MM').format(dt);
    } catch (_) {
      return iso;
    }
  }

  /// Метка даты для разделителя в ленте.
  static String dateLabel(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      if (msgDay == today) return 'Сегодня';
      if (msgDay == today.subtract(const Duration(days: 1))) return 'Вчера';
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
