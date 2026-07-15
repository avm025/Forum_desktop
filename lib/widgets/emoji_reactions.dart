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

/// Ряд реакций-эмодзи под сообщением — в одну строку, по одному чипу на автора.
class EmojiReactions extends StatelessWidget {
  final List<MessageEmojiModel> reactions;
  final String currentUserName;
  final String currentUserId;
  final void Function(String emoji, {required bool remove})? onReactionTap;

  const EmojiReactions({
    super.key,
    required this.reactions,
    this.currentUserName = '',
    this.currentUserId = '',
    this.onReactionTap,
  });

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
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
      final count = reaction.usrName.length;
      for (var i = 0; i < count; i++) {
        final uid = i < reaction.usrIds.length ? reaction.usrIds[i].trim() : '';
        var name = reaction.usrName[i].trim();
        final isMine = (mineId.isNotEmpty && ReactionUtils.sameUserId(uid, mineId)) ||
            (reaction.my &&
                (ReactionUtils.sameUserId(uid, mineId) || uid.isEmpty));

        if (name.isEmpty && isMine) {
          name = mineName;
        }

        final authorKey = uid.isNotEmpty ? uid : '_name:$name';
        if (authorKey == '_name:') continue;

        byAuthor[authorKey] = _ReactionDisplayItem(
          emoji: reaction.emoji,
          userName: name,
          userId: uid,
          isMine: isMine,
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
                item: items[i],
                palette: p,
                onTap: onReactionTap == null
                    ? null
                    : () => onReactionTap!(
                          items[i].emoji,
                          remove: items[i].isMine,
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
  final VoidCallback? onTap;

  const _ReactionChip({
    required this.item,
    required this.palette,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final author = EmojiReactions._initials(item.userName);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: item.isMine
                ? palette.purple.withValues(alpha: 0.25)
                : palette.bg3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.isMine ? palette.purple : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 14)),
              if (author.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  author,
                  style: TextStyle(
                    color: item.isMine ? palette.purple : palette.text2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
