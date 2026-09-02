import 'package:flutter/material.dart';

import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import 'chat_view.dart';

/// Панель текущего чата.
///
/// Без вложенного [Navigator] и без IndexedStack: OverlayPortal внутри
/// Navigator под LayoutBuilder/IndexedStack даёт краш
/// `_RenderLayoutBuilder was mutated`.
class ChatPanelHost extends StatelessWidget {
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

  DialogsListViewModel? _dialogFor(String id) {
    for (final d in dialogs) {
      if (AppState.dlgIdsEqual(d.id, id)) return d;
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final current = selected;
    if (current == null) return emptyChild;

    final id = current.id?.trim();
    if (id == null || id.isEmpty) return emptyChild;

    final dialog = _dialogFor(id) ?? current;

    return ChatView(
      key: ValueKey<String>('chat_panel_$id'),
      dialog: dialog,
      showBack: showBack,
    );
  }
}
