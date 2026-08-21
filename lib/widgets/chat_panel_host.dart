import 'package:flutter/material.dart';

import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import 'chat_view.dart';

/// Держит открытые чаты живыми при переключении — сохраняет ScrollController.
class ChatPanelHost extends StatefulWidget {
  final DialogsListViewModel? selected;
  final List<DialogsListViewModel> dialogs;
  final bool showBack;
  final Widget emptyChild;

  const ChatPanelHost({
    super.key,
    required this.selected,
    required this.dialogs,
    this.showBack = false,
    required this.emptyChild,
  });

  @override
  State<ChatPanelHost> createState() => _ChatPanelHostState();
}

class _ChatPanelHostState extends State<ChatPanelHost> {
  static const _maxOpenChats = 12;

  final List<String> _openIds = [];

  @override
  void initState() {
    super.initState();
    _rememberOpen(widget.selected?.id);
  }

  @override
  void didUpdateWidget(ChatPanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberOpen(widget.selected?.id);
  }

  void _rememberOpen(String? id) {
    if (id == null || id.trim().isEmpty) return;
    final normalized = id.trim();
    if (_openIds.any((open) => AppState.dlgIdsEqual(open, normalized))) return;
    _openIds.add(normalized);
    while (_openIds.length > _maxOpenChats) {
      _openIds.removeAt(0);
    }
  }

  int _selectedIndex() {
    final id = widget.selected?.id;
    if (id == null) return -1;
    for (var i = 0; i < _openIds.length; i++) {
      if (AppState.dlgIdsEqual(_openIds[i], id)) return i;
    }
    return -1;
  }

  DialogsListViewModel? _dialogFor(String id) {
    for (final d in widget.dialogs) {
      if (AppState.dlgIdsEqual(d.id, id)) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    if (selected == null) return widget.emptyChild;

    final index = _selectedIndex();
    if (index < 0) return widget.emptyChild;

    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: [
        for (final id in _openIds)
          _buildPanel(id),
      ],
    );
  }

  Widget _buildPanel(String id) {
    final dialog = _dialogFor(id);
    if (dialog == null) {
      return const SizedBox.shrink();
    }
    // Локальный Navigator: профиль собеседника открывается поверх чата
    // (как push в iOS), не перекрывая список диалогов в wide-layout.
    return Navigator(
      key: ValueKey<String>('chat_nav_$id'),
      onGenerateRoute: (_) {
        return MaterialPageRoute<void>(
          builder: (_) => ChatView(
            key: PageStorageKey<String>('chat_panel_$id'),
            dialog: dialog,
            showBack: widget.showBack,
          ),
        );
      },
    );
  }
}
