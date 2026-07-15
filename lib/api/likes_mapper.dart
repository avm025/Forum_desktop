import '../models/message_emoji_model.dart';
import '../utils/reaction_utils.dart';

/// Разбор поля `likes` и ответа WS `add_like` (WS_MSG_LIKES.md).
class LikesMapper {
  LikesMapper._();

  static List<MessageEmojiModel> parseList(
    dynamic raw, {
    String? currentUserId,
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
    return normalizeOnePerUser(parsed, currentUserId: currentUserId);
  }

  static List<MessageEmojiModel> parseAddLikeResponse(
    Map<String, dynamic> map, {
    String? currentUserId,
  }) {
    final body = map['body'];
    if (body is! List || body.isEmpty) return <MessageEmojiModel>[];
    final first = body.first;
    if (first is! Map) return <MessageEmojiModel>[];
    return parseList(first['data'], currentUserId: currentUserId);
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
        final uid = i < reaction.usrIds.length
            ? reaction.usrIds[i].trim()
            : '';
        final key = uid.isNotEmpty ? uid : '_name:${reaction.usrName[i].trim()}';
        if (key == '_name:') continue;

        winners[key] = _ReactionUserEntry(
          emoji: reaction.emoji,
          usrId: uid,
          usrName: reaction.usrName[i].trim(),
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

    return byEmoji.entries
        .map((e) {
          final users = e.value;
          var my = false;
          if (myId.isNotEmpty) {
            my = users.any((u) => ReactionUtils.sameUserId(u.usrId, myId));
          }
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
        })
        .toList();
  }

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
