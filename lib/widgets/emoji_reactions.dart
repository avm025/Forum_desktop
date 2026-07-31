import 'package:flutter/material.dart';

import '../models/message_emoji_model.dart';
import '../theme/app_theme.dart';
import '../utils/reaction_utils.dart';

class _ReactionDisplayItem {
  final String emoji;
  final String userName;
  final String userId;
  final bool isMine;

  const _ReactionDisplayItem({
    required this.emoji,
    required this.userName,
    required this.userId,
    required this.isMine,
  });
}

/// Ряд реакций: подпись — инициалы «ИФ»; свои с тапом на снятие.
class EmojiReactions extends StatelessWidget {
  final List<MessageEmojiModel> reactions;
  final String currentUserName;
  final String currentUserId;
  /// Свой (фиолетовый) пузырь — светлая подпись, иначе она сливается с фоном.
  final bool onAccent;
  final void Function(String emoji, {required bool remove})? onReactionTap;

  const EmojiReactions({
    super.key,
    required this.reactions,
    this.currentUserName = '',
    this.currentUserId = '',
    this.onAccent = false,
    this.onReactionTap,
  });

  /// Имя одна буква + фамилия одна буква (например «АП»).
  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    String letter(String s) {
      final chars = s.characters;
      return chars.isEmpty ? '' : chars.first.toUpperCase();
    }

    if (parts.length == 1) {
      final only = letter(parts.first);
      return only;
    }
    return '${letter(parts[0])}${letter(parts[1])}';
  }

  static List<_ReactionDisplayItem> _expandReactions(
    List<MessageEmojiModel> reactions,
    String currentUserName,
    String currentUserId,
  ) {
    final mineId = currentUserId.trim();
    final mineName = currentUserName.trim().isNotEmpty
        ? currentUserName.trim()
        : 'Вы';
    final byAuthor = <String, _ReactionDisplayItem>{};

    for (final reaction in reactions) {
      final count = reaction.usrName.length > reaction.usrIds.length
          ? reaction.usrName.length
          : reaction.usrIds.length;

      for (var i = 0; i < count; i++) {
        final uid = i < reaction.usrIds.length ? reaction.usrIds[i].trim() : '';
        var name = i < reaction.usrName.length ? reaction.usrName[i].trim() : '';

        final isMine = (mineId.isNotEmpty &&
                ReactionUtils.sameUserId(uid, mineId)) ||
            (reaction.my &&
                (uid.isEmpty || ReactionUtils.sameUserId(uid, mineId)));

        if (isMine) {
          name = mineName;
        }
        if (name.isEmpty) continue;

        final authorKey =
            uid.isNotEmpty ? uid : (isMine ? '_me' : '_name:$name');
        byAuthor[authorKey] = _ReactionDisplayItem(
          emoji: reaction.emoji,
          userName: name,
          userId: uid.isNotEmpty ? uid : (isMine ? mineId : ''),
          isMine: isMine,
        );
      }

      if (reaction.my && !byAuthor.values.any((e) => e.isMine)) {
        byAuthor['_me'] = _ReactionDisplayItem(
          emoji: reaction.emoji,
          userName: mineName,
          userId: mineId,
          isMine: true,
        );
      }
    }

    return byAuthor.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = _expandReactions(reactions, currentUserName, currentUserId);
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _ReactionChip(
                key: ValueKey(
                  '${items[i].userId}|${items[i].emoji}|${items[i].isMine}',
                ),
                item: items[i],
                palette: p,
                onAccent: onAccent,
                onTap: onReactionTap == null || !items[i].isMine
                    ? null
                    : () => onReactionTap!(
                          items[i].emoji,
                          remove: true,
                        ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final _ReactionDisplayItem item;
  final ForumPalette palette;
  final bool onAccent;
  final VoidCallback? onTap;

  const _ReactionChip({
    super.key,
    required this.item,
    required this.palette,
    this.onAccent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Своя реакция всегда с инициалами; чужая — тоже, если есть имя.
    final label = EmojiReactions.initials(item.userName);
    final showLabel = label.isNotEmpty || item.isMine;
    final text = label.isNotEmpty ? label : (item.isMine ? 'Вы' : '');

    final Color bg;
    final Color border;
    final Color labelColor;
    if (onAccent) {
      // На фиолетовом пузыре фиолетовый текст нечитаем — светлая схема.
      bg = Colors.white.withValues(alpha: item.isMine ? 0.28 : 0.18);
      border = item.isMine
          ? Colors.white.withValues(alpha: 0.85)
          : Colors.transparent;
      labelColor = Colors.white;
    } else if (item.isMine) {
      bg = palette.purple.withValues(alpha: 0.25);
      border = palette.purple;
      labelColor = palette.purple;
    } else {
      bg = palette.bg3;
      border = Colors.transparent;
      labelColor = palette.text2;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 14)),
              if (showLabel && text.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  text,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
