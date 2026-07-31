import '../models/message_emoji_model.dart';
import '../utils/reaction_utils.dart';

/// Разбор поля `likes` и ответа WS `add_like` (WS_MSG_LIKES.md).
class LikesMapper {
  LikesMapper._();

  static List<MessageEmojiModel> parseList(
    dynamic raw, {
    String? currentUserId,
    String? currentUserName,
  }) {
    if (raw is! List) return <MessageEmojiModel>[];
    final parsed = raw
        .whereType<Map>()
        .map((e) => _parseLikeEntry(
              Map<String, dynamic>.from(e),
              currentUserId: currentUserId,
            ))
        .where((e) => e.emoji.isNotEmpty)
        .toList();
    return enrichCurrentUser(
      normalizeOnePerUser(parsed, currentUserId: currentUserId),
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    );
  }

  static List<MessageEmojiModel> parseAddLikeResponse(
    Map<String, dynamic> map, {
    String? currentUserId,
    String? currentUserName,
  }) {
    List<MessageEmojiModel> likes = const [];

    final body = map['body'];
    if (body is List && body.isNotEmpty) {
      final first = body.first;
      if (first is Map) {
        likes = parseList(
          first['data'] ?? first['likes'],
          currentUserId: currentUserId,
          currentUserName: currentUserName,
        );
      }
    }

    if (likes.isEmpty) {
      final data = map['data'];
      if (data is Map) {
        likes = parseList(
          data['likes'] ?? data['data'],
          currentUserId: currentUserId,
          currentUserName: currentUserName,
        );
      } else if (data is List) {
        likes = parseList(
          data,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
        );
      }
    }

    if (likes.isEmpty) {
      likes = parseList(
        map['likes'],
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );
    }

    return enrichCurrentUser(
      likes,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    );
  }

  /// В ответе есть явный список likes (в т.ч. пустой `body: []` у del_like — нет).
  static bool responseHasLikesPayload(Map<String, dynamic> map) {
    final body = map['body'];
    if (body is List) {
      if (body.isEmpty) return false;
      final first = body.first;
      if (first is Map) {
        final data = first['data'] ?? first['likes'];
        if (data is List) return true;
      }
    }

    final data = map['data'];
    if (data is Map) {
      final likes = data['likes'] ?? data['data'];
      if (likes is List) return true;
    } else if (data is List) {
      // data как список likes (не поля запроса add/del_like).
      if (data.isEmpty) return true;
      final first = data.first;
      if (first is Map &&
          (first.containsKey('emoji') || first.containsKey('arr'))) {
        return true;
      }
    }

    return map['likes'] is List;
  }

  /// Подставить имя текущего пользователя в его реакции (сервер часто шлёт пустое).
  static List<MessageEmojiModel> enrichCurrentUser(
    List<MessageEmojiModel> reactions, {
    String? currentUserId,
    String? currentUserName,
  }) {
    final myId = currentUserId?.trim() ?? '';
    final myName = currentUserName?.trim() ?? '';
    if (myId.isEmpty || myName.isEmpty) return reactions;

    for (final reaction in reactions) {
      var touched = false;
      final names = List<String>.from(reaction.usrName);
      final ids = List<String>.from(reaction.usrIds);

      for (var i = 0; i < ids.length; i++) {
        if (!ReactionUtils.sameUserId(ids[i], myId)) continue;
        while (names.length <= i) {
          names.add('');
        }
        names[i] = myName;
        touched = true;
      }

      if (reaction.my && !touched) {
        if (ids.isEmpty) {
          ids.add(myId);
          names.add(myName);
        } else {
          // my=true, но id не совпал — всё равно подпишем первую запись без имени
          for (var i = 0; i < names.length; i++) {
            if (names[i].trim().isEmpty) {
              names[i] = myName;
              if (i < ids.length && ids[i].trim().isEmpty) {
                ids[i] = myId;
              }
              touched = true;
              break;
            }
          }
          if (!touched) {
            ids.add(myId);
            names.add(myName);
          }
        }
        touched = true;
      }

      if (touched) {
        reaction.usrName = names;
        reaction.usrIds = ids;
        reaction.my = true;
        reaction.qty = names.length;
      }
    }
    return reactions;
  }

  /// У каждого автора — не более одной реакции (последняя побеждает).
  static List<MessageEmojiModel> normalizeOnePerUser(
    List<MessageEmojiModel> reactions, {
    String? currentUserId,
  }) {
    final myId = currentUserId?.trim() ?? '';
    final winners = <String, _ReactionUserEntry>{};

    for (final reaction in reactions) {
      final count = reaction.usrName.length;
      for (var i = 0; i < count; i++) {
        final uid =
            i < reaction.usrIds.length ? reaction.usrIds[i].trim() : '';
        final name = reaction.usrName[i].trim();
        final key = uid.isNotEmpty ? uid : '_name:$name';
        if (key == '_name:') continue;

        winners[key] = _ReactionUserEntry(
          emoji: reaction.emoji,
          usrId: uid,
          usrName: name,
          avaColor: i < reaction.avaColor.length ? reaction.avaColor[i] : 0,
          avatar: i < reaction.avatars.length ? reaction.avatars[i] : '',
          date: i < reaction.date.length ? reaction.date[i] : '',
        );
      }
    }

    final byEmoji = <String, List<_ReactionUserEntry>>{};
    for (final entry in winners.values) {
      byEmoji.putIfAbsent(entry.emoji, () => []).add(entry);
    }

    return byEmoji.entries.map((e) {
      final users = e.value;
      final my = myId.isNotEmpty &&
          users.any((u) => ReactionUtils.sameUserId(u.usrId, myId));
      return MessageEmojiModel(
        emoji: e.key,
        my: my,
        qty: users.length,
        usrName: users.map((u) => u.usrName).toList(),
        usrIds: users.map((u) => u.usrId).toList(),
        avaColor: users.map((u) => u.avaColor).toList(),
        avatars: users.map((u) => u.avatar).toList(),
        date: users.map((u) => u.date).toList(),
      );
    }).toList();
  }

  /// @nodoc Совместимость со старым именем API.
  static List<MessageEmojiModel> mergeByEmoji(
    List<MessageEmojiModel> reactions, {
    String? currentUserId,
  }) =>
      normalizeOnePerUser(reactions, currentUserId: currentUserId);

  static MessageEmojiModel _parseLikeEntry(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final emoji = json['emoji']?.toString() ?? '';
    final arr = json['arr'];
    final users = <Map<String, dynamic>>[];
    if (arr is List) {
      for (final item in arr) {
        if (item is Map) users.add(Map<String, dynamic>.from(item));
      }
    }
    final uniqueUsers = _dedupeUsers(users);

    final qtyRaw = json['qty'];
    final qty = qtyRaw is int
        ? qtyRaw
        : int.tryParse(qtyRaw?.toString() ?? '') ?? uniqueUsers.length;

    final usrNames = <String>[];
    final usrIds = <String>[];
    final avaColors = <int>[];
    final avatars = <String>[];
    final dates = <String>[];
    var my = false;

    for (final u in uniqueUsers) {
      final uid = u['usr_id']?.toString() ?? '';
      usrNames.add(u['usr_name']?.toString() ?? '');
      usrIds.add(uid);
      avaColors.add(_parseInt(
        u['usr_col_ava_id'] ?? u['ava_color'],
      ));
      avatars.add(u['usr_ava']?.toString() ?? '');
      dates.add(u['dttmcr']?.toString() ?? '');
      if (!my &&
          currentUserId != null &&
          currentUserId.isNotEmpty &&
          ReactionUtils.sameUserId(uid, currentUserId)) {
        my = true;
      }
    }

    return MessageEmojiModel(
      emoji: emoji,
      my: my,
      qty: qty > 0 ? qty : uniqueUsers.length,
      usrName: usrNames,
      usrIds: usrIds,
      avaColor: avaColors,
      avatars: avatars,
      date: dates,
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Один автор — одна запись в `arr` (сервер иногда шлёт дубликаты).
  static List<Map<String, dynamic>> _dedupeUsers(
    List<Map<String, dynamic>> users,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final u in users) {
      final uid = u['usr_id']?.toString().trim() ?? '';
      final name = u['usr_name']?.toString().trim() ?? '';
      final key = uid.isNotEmpty ? uid : '_name:$name';
      if (key == '_name:') continue;

      final existing = byKey[key];
      if (existing == null ||
          _isNewerTimestamp(
            u['dttmcr']?.toString(),
            existing['dttmcr']?.toString(),
          )) {
        byKey[key] = u;
      }
    }
    return byKey.values.toList();
  }

  static bool _isNewerTimestamp(String? a, String? b) {
    if (b == null || b.isEmpty) return true;
    if (a == null || a.isEmpty) return false;
    return a.compareTo(b) >= 0;
  }
}

class _ReactionUserEntry {
  final String emoji;
  final String usrId;
  final String usrName;
  final int avaColor;
  final String avatar;
  final String date;

  const _ReactionUserEntry({
    required this.emoji,
    required this.usrId,
    required this.usrName,
    required this.avaColor,
    required this.avatar,
    required this.date,
  });
}
