import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/mention_markup.dart';
import 'avatar_widget.dart';

/// Выпадающий список участников для `@` (как Telegram Desktop).
///
/// Аватары только инициалами (без CachedNetworkImage) — иначе при закрытии
/// пикера dispose десятков картинок на секунды блокирует курсор в TextField.
class MentionPicker extends StatelessWidget {
  final List<MentionCandidate> candidates;
  final int selectedIndex;
  final ValueChanged<MentionCandidate> onSelect;
  final ValueChanged<int> onHighlight;

  const MentionPicker({
    super.key,
    required this.candidates,
    required this.selectedIndex,
    required this.onSelect,
    required this.onHighlight,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (candidates.isEmpty) return const SizedBox.shrink();

    final index = selectedIndex.clamp(0, candidates.length - 1);

    return Material(
      color: p.bg2,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          itemCount: candidates.length,
          itemBuilder: (context, i) {
            final c = candidates[i];
            final selected = i == index;
            return MouseRegion(
              onEnter: (_) {
                if (i != index) onHighlight(i);
              },
              child: InkWell(
                onTap: () => onSelect(c),
                child: ColoredBox(
                  color: selected
                      ? p.purple.withValues(alpha: 0.22)
                      : Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        if (c.special)
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: p.purple.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '@',
                              style: TextStyle(
                                color: p.purple,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          AvatarWidget(
                            name: c.title,
                            avatarUrl: '',
                            colAvaId: c.colAvaId,
                            online: c.online,
                            size: 36,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.special ? '@${c.title}' : c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? p.purple : p.text1,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (c.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  c.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.text2,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
