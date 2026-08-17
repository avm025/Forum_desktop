import 'dart:convert';

import 'package:intl/intl.dart';

import '../api/api_config.dart';
import '../calls/call_message_display.dart';
import '../models/chat_type.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/group_additional_info_model.dart';

/// Преобразование JSON диалога с сервера в [DialogsListViewModel].
///
/// Как в Forum_ios `DataConverter`: `last_msg` — объект
/// `{ type, body, status, fr_id, fr_name, id, dttmcr }`, а не сырой JSON body.
class DialogMapper {
  DialogMapper._();

  static DialogsListViewModel fromServerJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final isGrp = _parseInt(json['is_grp']) == 1;
    final dlgId =
        json['dlg_id']?.toString() ?? json['id']?.toString() ?? '';
    final usr1Id = json['usr1_id']?.toString() ?? '';
    final usr2Id = json['usr2_id']?.toString() ?? '';

    // Как iOS DataConverter: для 1:1 берём поля собеседника, не usr1_*.
    var avatarPath =
        (json['img_url'] ?? json['ava'] ?? '').toString().trim();
    var chatName = json['name']?.toString() ?? '';
    var usrId = json['usr_id']?.toString();
    var phone = json['phone']?.toString();
    var colorHex = (json['color'] ?? '').toString().trim();
    var colAvaId = _parseInt(
      json['col_ava_id'] ?? json['grp_col_ava_id'],
      fallback: 1,
    );
    if (colAvaId <= 0) colAvaId = 1;

    if (!isGrp &&
        !DialogsListViewModel.isPlaceholderDlgId(dlgId) &&
        usr1Id.isNotEmpty &&
        usr2Id.isNotEmpty) {
      final meIsUsr1 = _sameUserId(currentUserId, usr1Id);
      if (meIsUsr1) {
        if (chatName.trim().isEmpty) {
          chatName = json['usr2_name']?.toString() ?? '';
        }
        phone = json['usr2_phone']?.toString() ?? phone;
        usrId = usr2Id;
        final peerAva = (json['usr2_ava'] ?? '').toString().trim();
        if (peerAva.isNotEmpty) avatarPath = peerAva;
        colAvaId = _parseInt(json['usr2_col_ava_id'], fallback: colAvaId);
        final peerColor = (json['usr2_color'] ?? '').toString().trim();
        if (peerColor.isNotEmpty) colorHex = peerColor;
      } else {
        if (chatName.trim().isEmpty) {
          chatName = json['usr1_name']?.toString() ?? '';
        }
        phone = json['usr1_phone']?.toString() ?? phone;
        usrId = usr1Id;
        final peerAva = (json['usr1_ava'] ?? '').toString().trim();
        if (peerAva.isNotEmpty) avatarPath = peerAva;
        colAvaId = _parseInt(json['usr1_col_ava_id'], fallback: colAvaId);
        final peerColor = (json['usr1_color'] ?? '').toString().trim();
        if (peerColor.isNotEmpty) colorHex = peerColor;
      }
    } else if (!isGrp) {
      // Контакт без диалога (dlg_id=0) или неполный 1:1.
      final fallbackAva = (json['usr1_ava'] ?? json['usr2_ava'] ?? '')
          .toString()
          .trim();
      if (avatarPath.isEmpty && fallbackAva.isNotEmpty) {
        avatarPath = fallbackAva;
      }
      phone ??= json['usr1_phone']?.toString() ?? json['usr2_phone']?.toString();
      if ((usrId == null || usrId.isEmpty) && usr1Id.isNotEmpty) {
        usrId = _sameUserId(currentUserId, usr1Id) ? usr2Id : usr1Id;
        if (usrId.isEmpty) usrId = usr1Id;
      }
    }

    // Как iOS: selectedAvatarColorId по умолчанию 1.
    if (colAvaId <= 0) colAvaId = 1;

    final last = _parseLastMsg(
      json['last_msg'],
      isGroup: isGrp,
      currentUserId: currentUserId,
    );

    return DialogsListViewModel(
      id: dlgId,
      usr_id: usrId,
      ai: _parseInt(json['ai']),
      // CDN fileServer (как GL.file_server), не API-хост :7770.
      avatar: ApiConfig.resolveAssetUrl(avatarPath),
      colAvaId: colAvaId,
      avatarColor: colorHex.isNotEmpty
          ? ['#${colorHex.replaceFirst('#', '')}']
          : null,
      chatName: chatName,
      last_msg: last.text,
      last_msg_id: last.id,
      last_msg_fr_id: last.frId.isNotEmpty
          ? last.frId
          : (json['usr1_id']?.toString() ?? ''),
      last_msg_fr_name: last.frName.isNotEmpty
          ? last.frName
          : (json['usr1_name']?.toString() ?? ''),
      last_msg_dttmcr: last.time.isNotEmpty
          ? last.time
          : _formatTime(json['dttmup']?.toString() ?? ''),
      last_msg_status: last.status,
      unread: _parseInt(json['unread']),
      chatType: isGrp ? ChatType.groupChat : ChatType.privateChat,
      isGrp: isGrp,
      pin: _parseInt(json['pin']),
      phone: phone,
      fav: _parseInt(json['fav']) == 1,
      online: _parseInt(json['online']) == 1,
      groupAditionalInfo: GroupAditionalInfoModel(
        colAvalId: colAvaId,
        desc: json['about']?.toString(),
        nick: json['name']?.toString(),
      ),
    );
  }

  /// Человекочитаемый preview последнего сообщения (как iOS DataConverter).
  static String previewFromLastMsg(
    dynamic raw, {
    String? currentUserId,
  }) =>
      _parseLastMsg(
        raw,
        isGroup: false,
        currentUserId: currentUserId,
      ).text;

  static _LastMsg _parseLastMsg(
    dynamic raw, {
    required bool isGroup,
    String? currentUserId,
  }) {
    if (raw == null) return const _LastMsg();

    Map<String, dynamic>? map;
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return const _LastMsg();
      // Иногда last_msg приходит как JSON-строка body (`{"desc":...,"files":...}`).
      if (s.startsWith('{')) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) {
            // Если это уже last_msg-объект с type — разбираем как объект.
            if (decoded.containsKey('type') || decoded.containsKey('body')) {
              map = Map<String, dynamic>.from(decoded);
            } else {
              // Это body вложения — превращаем в preview.
              return _LastMsg(text: _previewFromBodyJson(decoded, typeHint: null));
            }
          }
        } catch (_) {
          if (_looksLikeAttachmentJson(s)) {
            return const _LastMsg(text: 'Файл');
          }
          return _LastMsg(text: s);
        }
      } else {
        return _LastMsg(text: s);
      }
    }

    if (map == null) return const _LastMsg();

    final type = map['type']?.toString() ?? '';
    final bodyRaw = map['body'];
    final frId = map['fr_id']?.toString() ?? '';
    final text = _previewForType(
      type: type,
      bodyRaw: bodyRaw,
      frId: frId,
      currentUserId: currentUserId,
    );

    var frName = '';
    if (isGroup) {
      frName = map['fr_name']?.toString() ?? '';
    }

    final id = map['id']?.toString() ?? '';
    final status = map['status'] is int
        ? map['status'] as int
        : int.tryParse(map['status']?.toString() ?? '') ?? -2;
    final time = _formatTime(map['dttmcr']?.toString() ?? '');

    return _LastMsg(
      text: text,
      id: id,
      frId: frId,
      frName: frName,
      status: status,
      time: time,
    );
  }

  static String _previewForType({
    required String type,
    required dynamic bodyRaw,
    String? frId,
    String? currentUserId,
  }) {
    final t = type.toLowerCase();
    switch (t) {
      case 'img':
      case 'image':
        return 'Фотография';
      case 'mp4':
      case 'video':
        return 'Видео';
      case 'voice':
        return 'Голосовое сообщение';
      case 'media':
        return 'Медиафайлы';
      case 'call':
        return CallMessageDisplay.tryResolve(
              bodyRaw: bodyRaw,
              frId: frId,
              currentUserId: currentUserId,
            )?.previewText ??
            'Вызов';
      case 'geo':
        final geo = _asMap(bodyRaw);
        if (geo != null) {
          final adrs =
              (geo['adrs'] ?? geo['address'])?.toString().trim() ?? '';
          return adrs.isNotEmpty ? 'Геопозиция: $adrs' : 'Геопозиция';
        }
        return 'Геопозиция';
      case 'file':
        final file = _asMap(bodyRaw);
        if (file != null) {
          return _previewFromBodyJson(file, typeHint: 'file');
        }
        return 'Файл';
      default:
        // txt / неизвестный — body может быть строкой или JSON.
        if (bodyRaw == null) return '';
        if (bodyRaw is String) {
          final s = bodyRaw.trim();
          if (s.startsWith('{')) {
            final m = _asMap(s);
            if (m != null) {
              // Call body без type в last_msg-объекте.
              if (m.containsKey('media') &&
                  (m.containsKey('type') || m.containsKey('call_type'))) {
                return CallMessageDisplay.tryResolve(
                      bodyRaw: m,
                      frId: frId,
                      currentUserId: currentUserId,
                    )?.previewText ??
                    'Вызов';
              }
              return _previewFromBodyJson(m, typeHint: null);
            }
            if (_looksLikeAttachmentJson(s)) return 'Файл';
          }
          return s;
        }
        if (bodyRaw is Map) {
          return _previewFromBodyJson(
            Map<String, dynamic>.from(bodyRaw),
            typeHint: null,
          );
        }
        return bodyRaw.toString();
    }
  }

  /// Preview из body вложения: `{"desc":"","files":[...],"title":"..."}`.
  static String _previewFromBodyJson(
    Map<dynamic, dynamic> body, {
    required String? typeHint,
  }) {
    final desc = body['desc']?.toString().trim() ?? '';
    if (desc.isNotEmpty) return desc;

    final title = body['title']?.toString().trim() ?? '';
    final files = body['files'];
    final hasFiles = files is List && files.isNotEmpty;

    String? firstTitle;
    String? firstKind;
    if (hasFiles && files.first is Map) {
      final f = Map<String, dynamic>.from(files.first as Map);
      firstTitle = (f['title'] ?? f['fname'])?.toString().trim();
      firstKind = f['kind']?.toString().toLowerCase();
    }

    final kind = firstKind ?? '';
    final hint = (typeHint ?? '').toLowerCase();

    final isMedia = hint == 'media' ||
        kind == 'img' ||
        kind == 'image' ||
        kind == 'png' ||
        kind == 'jpg' ||
        kind == 'jpeg' ||
        kind == 'gif' ||
        kind == 'webp' ||
        kind == 'mp4' ||
        kind == 'video' ||
        kind == 'mov';

    if (isMedia) {
      if (kind == 'mp4' || kind == 'video' || kind == 'mov') return 'Видео';
      return hasFiles && files.length > 1 ? 'Медиафайлы' : 'Фотография';
    }

    if (hint == 'file' || hasFiles || title.isNotEmpty) {
      final name = title.isNotEmpty
          ? title
          : (firstTitle != null && firstTitle.isNotEmpty ? firstTitle : '');
      if (name.isNotEmpty) return 'Файл: $name';
      if (hasFiles && files.length > 1) return 'Файлы (${files.length})';
      return 'Файл';
    }

    if (body.containsKey('adrs') || body.containsKey('lat')) {
      final adrs = (body['adrs'] ?? body['address'])?.toString().trim() ?? '';
      return adrs.isNotEmpty ? 'Геопозиция: $adrs' : 'Геопозиция';
    }

    // Не показываем сырой JSON в списке чатов.
    return '';
  }

  static Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final s = raw.trim();
      if (!s.startsWith('{')) return null;
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static bool _looksLikeAttachmentJson(String value) {
    final t = value.trimLeft();
    if (!t.startsWith('{')) return false;
    return t.contains('"files"') ||
        t.contains('"fname"') ||
        t.contains('"fdir"') ||
        (t.contains('"desc"') && t.contains('"kind"'));
  }

  static int _parseInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static bool _sameUserId(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    final xi = int.tryParse(x);
    final yi = int.tryParse(y);
    return xi != null && yi != null && xi == yi;
  }

  static String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      if (msgDay == today) {
        return DateFormat('HH:mm').format(dt);
      }
      if (msgDay == today.subtract(const Duration(days: 1))) {
        return 'вчера';
      }
      return DateFormat('dd.MM').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _LastMsg {
  final String text;
  final String id;
  final String frId;
  final String frName;
  final int status;
  final String time;

  const _LastMsg({
    this.text = '',
    this.id = '',
    this.frId = '',
    this.frName = '',
    this.status = -2,
    this.time = '',
  });
}
