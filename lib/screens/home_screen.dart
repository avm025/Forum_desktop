import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/api_log_screen.dart';
import '../screens/profile_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/chat_panel_host.dart';
import '../widgets/chat_pane_background.dart';
import '../widgets/dialogs_sidebar.dart';

/// Главный экран: адаптивный двухпанельный layout.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const double _twoPaneBreakpoint = 760;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Сохраняет State чата (в т.ч. запись голоса) при смене wide↔narrow.
  final GlobalKey _chatPanelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    switch (state) {
      case AppLifecycleState.resumed:
        app.setAppInForeground(true);
        app.onAppResumed();
      case AppLifecycleState.inactive:
        // macOS: потеря фокуса окна (другое приложение / свёртка).
        app.setAppInForeground(false);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        app.setAppInForeground(false);
      case AppLifecycleState.detached:
        app.setAppInForeground(false);
        unawaited(app.prepareForTerminate());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;

    final wide =
        MediaQuery.sizeOf(context).width >= HomeScreen._twoPaneBreakpoint;
    // Как у чатов: таббар внизу левой колонки (чаты / проекты / профиль).
    final navUnderLeft = wide &&
        (state.navTab == BottomNavTab.chats ||
            state.navTab == BottomNavTab.projects ||
            state.navTab == BottomNavTab.profile);

    return Scaffold(
      backgroundColor: p.bg1,
      body: Column(
        children: [
          if (state.emergencyMentionText != null)
            Material(
              color: p.purple,
              child: SafeArea(
                bottom: false,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.campaign_rounded,
                      color: Colors.white, size: 22),
                  title: Text(
                    state.emergencyMentionText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => state.clearEmergencyMention(),
                  ),
                  onTap: () {
                    final dlgId = state.emergencyMentionDlgId;
                    state.clearEmergencyMention(notify: false);
                    if (dlgId != null && dlgId.isNotEmpty) {
                      state.selectDialog(dlgId);
                    }
                  },
                ),
              ),
            ),
          Expanded(child: _buildBody(context, state, p, wide: wide)),
          if (!navUnderLeft)
            const SafeArea(
              top: false,
              child: ForumBottomNav(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppState state,
    ForumPalette p, {
    required bool wide,
  }) {
    // Без IndexedStack вкладок: неактивные вкладки с OverlayPortal
    // (поля ввода/скролл) при активации ломают layout.
    return switch (state.navTab) {
      BottomNavTab.chats => _buildChatsPane(context, state, p, wide: wide),
      BottomNavTab.projects =>
        _buildProjectsPane(context, state, p, wide: wide),
      BottomNavTab.newLog => const ApiLogScreen(),
      BottomNavTab.profile => ProfileScreen(showNavInLeftPane: wide),
    };
  }

  Widget _buildProjectsPane(
    BuildContext context,
    AppState state,
    ForumPalette p, {
    required bool wide,
  }) {
    if (!wide) {
      return _PlaceholderTab(palette: p, title: 'Проекты');
    }
    // Как чаты: слева контент + таббар, справа пустая панель.
    const leftW = 375.0;
    return Row(
      children: [
        SizedBox(
          width: leftW,
          child: Column(
            children: [
              Expanded(child: _PlaceholderTab(palette: p, title: 'Проекты')),
              const SafeArea(
                top: false,
                child: ForumBottomNav(),
              ),
            ],
          ),
        ),
        Container(width: 1, color: p.border1),
        const Expanded(child: ChatPaneBackground(child: SizedBox.expand())),
      ],
    );
  }

  Widget _buildChatsPane(
    BuildContext context,
    AppState state,
    ForumPalette p, {
    required bool wide,
  }) {
    final selected = state.selectedDialog;
    // MediaQuery вместо LayoutBuilder: иначе при смене чата OverlayPortal
    // (Scrollbar/Navigator) активируется внутри performLayout → краш.

    // Один и тот же GlobalKey: при пересечении breakpoint 760 панель чата
    // не пересоздаётся — запись голоса и поле ввода не сбрасываются.
    final chatPanel = ChatPanelHost(
      key: _chatPanelKey,
      selected: selected,
      dialogs: state.dialogs,
      showBack: !wide && selected != null,
      emptyChild: wide ? const _NoChatSelected() : const DialogsSidebar(),
    );

    if (wide) {
      return _ResizableChatsSplit(
        totalWidth: MediaQuery.sizeOf(context).width,
        chatPanel: chatPanel,
      );
    }

    return chatPanel;
  }
}

/// Двухпанельный режим: список чатов ↔ сообщения, ширина тянется мышкой.
class _ResizableChatsSplit extends StatefulWidget {
  final double totalWidth;
  final Widget chatPanel;

  const _ResizableChatsSplit({
    required this.totalWidth,
    required this.chatPanel,
  });

  @override
  State<_ResizableChatsSplit> createState() => _ResizableChatsSplitState();
}

class _ResizableChatsSplitState extends State<_ResizableChatsSplit> {
  static const _prefsKey = 'forum_sidebar_width';
  static const _defaultWidth = 375.0;
  static const _minSidebar = 220.0;
  /// В полноэкранном режиме можно сильно расширить список чатов.
  static const _maxSidebar = 1200.0;
  static const _minChat = 280.0;
  static const _dividerHitWidth = 8.0;

  double _sidebarWidth = _defaultWidth;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _restoreWidth();
  }

  Future<void> _restoreWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefsKey);
      if (!mounted || saved == null) return;
      setState(() {
        _sidebarWidth = _clampWidth(saved, widget.totalWidth);
      });
    } catch (_) {}
  }

  Future<void> _persistWidth(double width) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKey, width);
    } catch (_) {}
  }

  double _clampWidth(double width, double totalWidth) {
    // Максимум — почти весь экран минус минимальная ширина чата.
    final maxByLayout = (totalWidth - _minChat).clamp(_minSidebar, _maxSidebar);
    return width.clamp(_minSidebar, maxByLayout.toDouble());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragging = true;
      _sidebarWidth = _clampWidth(
        _sidebarWidth + details.delta.dx,
        widget.totalWidth,
      );
    });
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() => _dragging = false);
    _persistWidth(_sidebarWidth);
  }

  @override
  void didUpdateWidget(covariant _ResizableChatsSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalWidth != widget.totalWidth) {
      final next = _clampWidth(_sidebarWidth, widget.totalWidth);
      if (next != _sidebarWidth) {
        _sidebarWidth = next;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = _clampWidth(_sidebarWidth, widget.totalWidth);

    return Row(
      children: [
        SizedBox(
          width: width,
          child: const Column(
            children: [
              Expanded(child: DialogsSidebar()),
              SafeArea(
                top: false,
                child: ForumBottomNav(),
              ),
            ],
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: () {
              setState(() => _dragging = false);
              _persistWidth(_sidebarWidth);
            },
            child: SizedBox(
              width: _dividerHitWidth,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: _dragging ? 3 : 1,
                  color: _dragging ? p.purple : p.border1,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.chatPanel),
      ],
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Как в Telegram Desktop: полупрозрачная «таблетка» по центру обоев.
    final bubbleColor = isDark
        ? const Color(0x591C1C1C) // ~35%
        : const Color(0x59000000);
    return ChatPaneBackground(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Text(
              'Выберите, кому хотели бы написать',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ),
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
