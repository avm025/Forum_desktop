import 'dart:convert';

import 'package:intl/intl.dart';

import '../api/api_config.dart';
import '../calls/call_message_display.dart';
import '../models/media_file.dart';
import '../models/message_emoji_model.dart';
import '../api/likes_mapper.dart';
import '../models/message_view_model.dart';
import '../utils/media_display_name.dart';
import '../utils/voice_histogram.dart';

/// Преобразование сообщений с сервера (msg_list / msg) → [MessageViewModel].
class MessageMapper {
  MessageMapper._();

  /// Список сообщений из ответа msg_list с группировкой аватаров.
  static List<MessageViewModel> fromMsgList(
    List<dynamic> raw, {
    String? currentUserId,
    String? currentUserName,
    bool isGroupChat = false,
  }) {
    final messages = raw
        .whereType<Map>()
        .map((e) => fromServerJson(
              Map<String, dynamic>.from(e),
              currentUserId: currentUserId,
              currentUserName: currentUserName,
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
    String? currentUserName,
  }) {
    final serverType = (json['type']?.toString() ?? 'txt').toLowerCase();
    final uiType = _mapType(serverType);
    final frId = json['fr_id']?.toString() ?? '';
    final my = currentUserId != null &&
        currentUserId.isNotEmpty &&
        frId == currentUserId;

    // body бывает JSON-строкой или уже объектом (WS/msg_list).
    final parsedBody = _parseBodyField(json['body']);
    final bodyRaw = parsedBody.raw;
    final bodyJson = parsedBody.map;

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
    var locationLive = false;
    MsgSize size = MsgSize.zero;

    final dttmcr = json['dttmcr']?.toString() ?? '';

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
        files = _parseFiles(
          bodyJson?['files'] ?? json['files'],
          dttmcr: dttmcr,
        );
        if (files.isNotEmpty) {
          size = MsgSize(files.first.widthValue, files.first.heightValue);
          fileTitle = files.first.title;
        }
      case 'file':
        // Подпись — только desc; сырой body JSON в чат не показываем
        // (тайлы файлов уже рисуются отдельно).
        desc = bodyJson?['desc']?.toString() ?? '';
        body = desc;
        text = desc;
        files = _parseFiles(bodyJson?['files'], dttmcr: dttmcr);
        if (files.isEmpty && bodyJson != null) {
          files = [_fileFromMap(bodyJson, dttmcr: dttmcr)];
        }
        if (files.isNotEmpty) {
          fileTitle = files.first.title;
          fileSize = files.first.humanSize;
          fileFormat = files.first.formatLabel;
        }
      case 'voice':
        final voiceBody = bodyJson ?? json;
        files = [_fileFromMap(voiceBody, dttmcr: dttmcr)];
        voiceHistogram = _parseHistogram(
          voiceBody['hist'] ?? voiceBody['voice_histogram'] ?? json['voice_histogram'],
        );
        desc = voiceBody['desc']?.toString() ?? '';
        body = 'Голосовое сообщение';
      case 'geo':
      case 'geotr':
        // geo — точка с adrs; geotr — live-трансляция { lat, lon, live, speed, comp }.
        final geo = bodyJson ?? const <String, dynamic>{};
        lat = _toDouble(
          geo['lat'] ?? geo['latitude'] ?? json['lat'] ?? json['latitude'],
        );
        lon = _toDouble(
          geo['lon'] ?? geo['longitude'] ?? json['lon'] ?? json['longitude'],
        );
        address = (geo['adrs'] ??
                    geo['address'] ??
                    json['adrs'] ??
                    json['address'])
                ?.toString()
                .trim() ??
            '';
        desc = geo['desc']?.toString() ?? '';
        final liveFlag = _parseLiveFlag(geo['live']);
        locationLive = liveFlag ?? (serverType == 'geotr');
        final trackEnded = serverType == 'geotr' && liveFlag == false;
        if (trackEnded) {
          address = 'Трансляция геопозиции завершена';
        } else if (address.isEmpty) {
          address = locationLive ? 'Трансляция геопозиции' : 'Геопозиция';
        }
        body = address;
        text = body;
      case 'call':
        // Сырой JSON оставляем в body (reply prn_body / parse).
        body = bodyRaw;
        final display = CallMessageDisplay.tryResolve(
          bodyRaw: bodyJson ?? bodyRaw,
          frId: frId,
          currentUserId: currentUserId,
        );
        final preview = display?.previewText ?? 'Вызов';
        text = preview;
        desc = preview;
      default:
        if (bodyJson != null) {
          desc = bodyJson['desc']?.toString() ?? '';
          body = desc.isNotEmpty ? desc : bodyRaw;
        }
    }

    final prnBody = json['prn_body']?.toString() ?? '';
    final prnType = json['prn_type']?.toString() ?? '';
    final prnBodyJson = _tryParseJson(prnBody);
    MediaFile? prnFirstFile;
    String resolvedPrnBody = prnBody;
    final prnTypeLower = prnType.toLowerCase();
    if (prnTypeLower == 'call') {
      // Для call в prn_body хранится сырой JSON исходного сообщения.
      resolvedPrnBody = prnBody;
    } else if (prnTypeLower == 'geo') {
      // Как iOS DataConverter: в превью ответа — только adrs.
      if (prnBodyJson != null) {
        final adrs = (prnBodyJson['adrs'] ?? prnBodyJson['address'])
                ?.toString()
                .trim() ??
            '';
        resolvedPrnBody = adrs.isNotEmpty ? adrs : prnBody;
      }
    } else if (prnBodyJson != null) {
      final prnFiles = _parseFiles(prnBodyJson['files'], dttmcr: dttmcr);
      if (prnFiles.isNotEmpty) prnFirstFile = prnFiles.first;
      resolvedPrnBody = prnBodyJson['desc']?.toString() ??
          prnBodyJson['body']?.toString() ??
          prnBody;
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
      dttmcr: dttmcr,
      dttmup: json['dttmup']?.toString() ?? '',
      dttmrd: json['dttmrd']?.toString() ?? '',
      dtshow: _formatTime(json['dttmcr']?.toString() ?? ''),
      status: _parseInt(json['status']),
      preview: ApiConfig.resolveAssetUrl(
        (json['preview'] ?? json['fr_ava'] ?? json['ava'] ?? json['usr_ava'])
            ?.toString(),
      ),
      url: ApiConfig.mediaUrl(json['url']?.toString()),
      fdir: json['fdir']?.toString() ?? '',
      hash: json['hash']?.toString() ?? '',
      prn_id: _normalizePrnId(json['prn_id']),
      prn_body: resolvedPrnBody,
      prn_fr_id: json['prn_fr_id']?.toString() ?? '',
      prn_fr_name: json['prn_fr_name']?.toString() ?? '',
      prn_type: prnType,
      prn_fileTitle: () {
        if (prnType.toLowerCase() == 'call') return '';
        if (prnFirstFile != null) return prnFirstFile.title;
        final t = prnBodyJson?['title']?.toString() ?? '';
        final f = prnBodyJson?['fname']?.toString() ?? '';
        if (t.isEmpty && f.isEmpty) return '';
        return MediaDisplayName.resolve(title: t, fname: f, dttmcr: dttmcr);
      }(),
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
      locationLive: locationLive,
      emoji: LikesMapper.parseList(
        json['likes'],
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      ),
    );
  }

  /// Обновить существующее сообщение данными с сервера (push msg / эхо).
  static void updateFromServer(MessageViewModel target, MessageViewModel incoming) {
    if (incoming.id.isNotEmpty) target.id = incoming.id;
    final incomingBody = incoming.body.trim();
    final incomingText = incoming.text.trim();
    if (incomingBody.isNotEmpty || target.body.trim().isEmpty) {
      target.body = incoming.body;
    }
    if (incomingText.isNotEmpty || target.text.trim().isEmpty) {
      target.text = incoming.text;
    }
    target.dttmcr = incoming.dttmcr;
    target.dttmup = incoming.dttmup;
    target.dttmrd = incoming.dttmrd;
    // Время в пузыре — исходное время создания, не время правки.
    target.dtshow = incoming.dtshow.isNotEmpty
        ? incoming.dtshow
        : target.dtshow;
    if (incoming.dttmup.trim().isNotEmpty &&
        incoming.dttmup.trim() != incoming.dttmcr.trim()) {
      target.editedLocal = true;
    }
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
    target.locationLive = incoming.locationLive;
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

      final sameAsPrev = prev != null && _sameSender(prev, m);
      final sameAsNext = next != null && _sameSender(m, next);

      // Шапка (имя + аватар сверху) у каждого нового отправителя —
      // текст / голос / медиа / файл — одинаково.
      m.showUserName = !sameAsPrev;
      // Кластер одного отправителя (скругления пузыря, отступы).
      m.avaOnTop = !sameAsPrev;
      m.avaOnBottom = !sameAsNext;
    }
  }

  static bool _sameSender(MessageViewModel a, MessageViewModel b) {
    if (a.my != b.my) return false;
    final aId = a.fr_id?.trim() ?? '';
    final bId = b.fr_id?.trim() ?? '';
    if (aId.isNotEmpty && bId.isNotEmpty) return aId == bId;
    // Один id пустой — не склеиваем (иначе voice/file без fr_id прячут шапку).
    if (aId.isNotEmpty || bId.isNotEmpty) return false;
    if (a.my && b.my) return true;
    final aName = a.fr_name.trim();
    final bName = b.fr_name.trim();
    if (aName.isNotEmpty && bName.isNotEmpty) return aName == bName;
    return false;
  }

  static String _mapType(String serverType) {
    switch (serverType.toLowerCase()) {
      case 'txt':
        return 'text';
      case 'geo':
      case 'geotr':
        return 'location';
      case 'img':
        return 'image';
      case 'media':
      case 'video':
        return 'media';
      default:
        return serverType.toLowerCase();
    }
  }

  /// `body` с сервера: строка JSON или уже распарсенный Map.
  static ({String raw, Map<String, dynamic>? map}) _parseBodyField(dynamic raw) {
    if (raw == null) return (raw: '', map: null);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      try {
        return (raw: jsonEncode(map), map: map);
      } catch (_) {
        return (raw: map.toString(), map: map);
      }
    }
    final s = raw.toString();
    return (raw: s, map: _tryParseJson(s));
  }

  static List<MediaFile> _parseFiles(dynamic raw, {String? dttmcr}) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => _fileFromMap(e, dttmcr: dttmcr))
        .toList();
  }

  static MediaFile _fileFromMap(Map<dynamic, dynamic> map, {String? dttmcr}) {
    final m = Map<String, dynamic>.from(map);
    final fdir = m['fdir']?.toString() ?? '';
    final fname = m['fname']?.toString() ?? '';
    final title = m['title']?.toString() ?? '';
    final name = fname.isNotEmpty ? fname : title;
    final display = MediaDisplayName.resolve(
      title: title,
      fname: name,
      dttmcr: dttmcr,
    );
    return MediaFile(
      hash: m['hash']?.toString() ?? '',
      url: m['url']?.toString().isNotEmpty == true
          ? ApiConfig.mediaUrl(m['url']?.toString())
          : ApiConfig.fileUrl(fdir, name),
      fname: name,
      fdir: fdir,
      kind: m['kind']?.toString() ?? m['type']?.toString() ?? '',
      preview: ApiConfig.mediaUrl(m['preview']?.toString()),
      title: display,
      size: _parseInt(m['size']),
      width: m['width']?.toString() ?? '0',
      height: m['height']?.toString() ?? '0',
      duration: _parseInt(m['duration']),
      uploaded: true,
    );
  }

  static List<int> _parseHistogram(dynamic raw) {
    // Forum_ios: hex `"038CF5…"` или `[Int]` / `voice_histogram`.
    return VoiceHistogram.parse(raw);
  }

  static Map<String, dynamic>? _tryParseJson(String raw) {
    if (raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  /// `null` — поля нет; иначе `live == 1` / `true`.
  static bool? _parseLiveFlag(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
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
