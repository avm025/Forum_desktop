import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'folder_actions.dart';

/// Ряд фильтров: Все / ИИ / Личное + папки диалогов с сервера.
class FilterTabs extends StatelessWidget {
  const FilterTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final tabs = state.tabs;

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _Tab(
                label: tab.label,
                badge: state.badgeForTab(tab.id),
                selected: state.activeTab == tab.id,
                palette: p,
                onTap: () => context.read<AppState>().selectTab(tab.id),
                onLongPress: () => FolderActions.showTabMenu(
                  context,
                  tabId: tab.id,
                  label: tab.label,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final int? badge;
  final bool selected;
  final ForumPalette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _Tab({
    required this.label,
    required this.badge,
    required this.selected,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.lime : palette.text2;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: palette.lime,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Color(0xFF0D0D0D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
