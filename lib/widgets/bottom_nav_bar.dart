import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Нижняя навигация: Чаты / Проекты / Задачи / Новое / Профиль.
class ForumBottomNav extends StatelessWidget {
  const ForumBottomNav({super.key});

  static const _compactWidth = 420;
  static const _ultraCompactWidth = 260;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final tab = state.navTab;

    return Container(
      decoration: BoxDecoration(
        color: p.bg1,
        border: Border(top: BorderSide(color: p.border1)),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = width < _compactWidth;
          final ultraCompact = width < _ultraCompactWidth;
          return Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.chat_bubble_outline,
                  label: 'Чаты',
                  active: tab == BottomNavTab.chats,
                  palette: p,
                  compact: compact,
                  ultraCompact: ultraCompact,
                  onTap: () => state.setNavTab(BottomNavTab.chats),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.work_outline,
                  label: 'Проекты',
                  badge: 3,
                  active: tab == BottomNavTab.projects,
                  palette: p,
                  compact: compact,
                  ultraCompact: ultraCompact,
                  onTap: () => state.setNavTab(BottomNavTab.projects),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.swap_horiz,
                  label: 'Задачи',
                  active: tab == BottomNavTab.tasks,
                  palette: p,
                  compact: compact,
                  ultraCompact: ultraCompact,
                  onTap: () => state.setNavTab(BottomNavTab.tasks),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.notifications_none,
                  label: 'Новое',
                  active: tab == BottomNavTab.newLog,
                  palette: p,
                  compact: compact,
                  ultraCompact: ultraCompact,
                  onTap: () => state.setNavTab(BottomNavTab.newLog),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.person_outline,
                  label: 'Профиль',
                  online: true,
                  active: tab == BottomNavTab.profile,
                  palette: p,
                  compact: compact,
                  ultraCompact: ultraCompact,
                  onTap: () => state.setNavTab(BottomNavTab.profile),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool online;
  final bool compact;
  final bool ultraCompact;
  final int? badge;
  final ForumPalette palette;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.active = false,
    this.online = false,
    this.compact = false,
    this.ultraCompact = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.lime : palette.text2;
    final iconSize = ultraCompact ? 20.0 : (compact ? 22.0 : 24.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ultraCompact ? 0 : 2,
            vertical: 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: ultraCompact ? 24 : 28,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, color: color, size: iconSize),
                    if (badge != null)
                      Positioned(
                        right: ultraCompact ? 2 : (compact ? 4 : 8),
                        top: ultraCompact ? 0 : -2,
                        child: ultraCompact
                            ? Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: palette.lime,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.lime,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$badge',
                                  style: const TextStyle(
                                    color: Color(0xFF0D0D0D),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    if (online)
                      Positioned(
                        right: ultraCompact ? 6 : (compact ? 8 : 12),
                        top: ultraCompact ? 1 : 0,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: palette.lime,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
