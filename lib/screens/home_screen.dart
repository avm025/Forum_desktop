import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/api_log_screen.dart';
import '../screens/profile_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/chat_panel_host.dart';
import '../widgets/dialogs_sidebar.dart';

/// Главный экран: адаптивный двухпанельный layout.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const double _sidebarWidth = 375;
  static const double _twoPaneBreakpoint = 760;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.bg1,
      body: Column(
        children: [
          Expanded(child: _buildBody(context, state, p)),
          const SafeArea(
            top: false,
            child: ForumBottomNav(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppState state, ForumPalette p) {
    return IndexedStack(
      index: _navTabIndex(state.navTab),
      sizing: StackFit.expand,
      children: [
        _buildChatsPane(context, state, p),
        _PlaceholderTab(palette: p, title: 'Проекты'),
        _PlaceholderTab(palette: p, title: 'Задачи'),
        const ApiLogScreen(),
        const ProfileScreen(),
      ],
    );
  }

  static int _navTabIndex(BottomNavTab tab) => switch (tab) {
        BottomNavTab.chats => 0,
        BottomNavTab.projects => 1,
        BottomNavTab.tasks => 2,
        BottomNavTab.newLog => 3,
        BottomNavTab.profile => 4,
      };

  Widget _buildChatsPane(
    BuildContext context,
    AppState state,
    ForumPalette p,
  ) {
    final selected = state.selectedDialog;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _twoPaneBreakpoint;

        if (wide) {
          return Row(
            children: [
              const SizedBox(
                width: _sidebarWidth,
                child: DialogsSidebar(),
              ),
              VerticalDivider(width: 1, color: p.border1),
              Expanded(
                child: ChatPanelHost(
                  selected: selected,
                  dialogs: state.dialogs,
                  emptyChild: _NoChatSelected(palette: p),
                ),
              ),
            ],
          );
        }

        return ChatPanelHost(
          selected: selected,
          dialogs: state.dialogs,
          showBack: selected != null,
          emptyChild: const DialogsSidebar(),
        );
      },
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  final ForumPalette palette;
  const _NoChatSelected({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.bg1,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 56, color: palette.text3),
          const SizedBox(height: 12),
          Text(
            'Выберите чат, чтобы начать переписку',
            style: TextStyle(color: palette.text2, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final ForumPalette palette;
  final String title;

  const _PlaceholderTab({required this.palette, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.bg1,
      alignment: Alignment.center,
      child: Text(
        title,
        style: TextStyle(color: palette.text2, fontSize: 18),
      ),
    );
  }
}
