import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dialogs_list_view_model.dart';
import '../models/global_search_chat_group.dart';
import '../models/global_search_hit.dart';
import '../models/global_search_scope.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import 'avatar_widget.dart';
import 'dialog_drop_target.dart';
import 'dialog_tile.dart';
import 'filter_tabs.dart';
import 'global_search_hit_tile.dart';
import 'global_search_scope_ribbon.dart';
import 'sidebar_header.dart';

/// Левая панель: список диалогов со всеми элементами управления.
class DialogsSidebar extends StatelessWidget {
  const DialogsSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final dialogs = state.dialogs;

    return Container(
      color: p.bg1,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => AttachmentSelection.clearIfOutside(),
        child: Column(
          children: [
            const SidebarHeader(),
            if (state.connectionStatus == ConnectionStatus.error)
              _ErrorBanner(
                message: state.connectionError ?? 'Ошибка подключения',
                onRetry: () => context.read<AppState>().retryConnection(),
              ),
            const GlobalSearchScopeRibbon(),
            if (state.globalSearchRibbonVisible) const SizedBox(height: 6),
            const SizedBox(height: 6),
            const FilterTabs(),
            const SizedBox(height: 4),
            Divider(height: 1, color: p.border1),
            Expanded(
              child: _buildBody(context, state, p, dialogs),
            ),
            if (state.dialogsSelectMode) const _DialogsSelectBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppState state,
    ForumPalette p,
    List<DialogsListViewModel> dialogs,
  ) {
    if (state.isLoading && state.connectionStatus != ConnectionStatus.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: p.purple),
            const SizedBox(height: 16),
            Text(
              'Подключение к серверу…',
              style: TextStyle(color: p.text2, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (state.showsGlobalMediaSearch) {
      return _GlobalMediaSearchBody(
        groups: state.globalSearchChatGroups,
        scope: state.globalSearchScope,
        searchQuery: state.search,
        preloadLabel: state.globalSearchPreloadLabel,
        preloading: state.globalSearchPreloading,
        selectedId: state.selectedId,
        activeHitKey: state.activeGlobalSearchHitKey,
        onOpenHit: (hit) => context.read<AppState>().openGlobalSearchHit(hit),
      );
    }

    if (dialogs.isEmpty) {
      return Center(
        child: Text(
          state.connectionStatus == ConnectionStatus.connected
              ? 'Чаты не найдены'
              : 'Нет данных',
          style: TextStyle(color: p.text2, fontSize: 15),
        ),
      );
    }

    return ValueListenableBuilder<String?>(
      valueListenable: DialogDropHover.id,
      builder: (context, hoverId, _) {
        return _DialogsScrollList(
          dialogs: dialogs,
          selectedId: state.selectedId,
          hoverId: hoverId,
          selectMode: state.dialogsSelectMode,
          onSelect: (id) {
            final app = context.read<AppState>();
            if (app.dialogsSelectMode) {
              app.toggleDialogChecked(id);
            } else {
              app.selectDialog(id);
            }
          },
        );
      },
    );
  }
}

class _DialogsSelectBottomBar extends StatelessWidget {
  const _DialogsSelectBottomBar();

  Future<void> _confirmDelete(BuildContext context) async {
    final app = context.read<AppState>();
    final count = app.selectedDialogsCount;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;
        return AlertDialog(
          backgroundColor: p.bg2,
          title: Text('Удалить чаты?', style: TextStyle(color: p.text1)),
          content: Text(
            count == 1
                ? 'Выбранный чат будет удалён из списка.'
                : 'Выбранные чаты ($count) будут удалены из списка.',
            style: TextStyle(color: p.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Отмена', style: TextStyle(color: p.text2)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Удалить', style: TextStyle(color: p.purple)),
            ),
          ],
        );
      },
    );
    if (ok == true && context.mounted) {
      context.read<AppState>().deleteSelectedDialogsFromSelectMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final hasSelection = state.selectedDialogsCount > 0;
    final readLabel = hasSelection ? 'Прочитать' : 'Прочитать все';

    return Material(
      color: p.bg2,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                TextButton(
                  onPressed: () =>
                      context.read<AppState>().markDialogsReadFromSelectMode(),
                  style: TextButton.styleFrom(
                    foregroundColor: p.purple,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    readLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: hasSelection ? () => _confirmDelete(context) : null,
                  style: TextButton.styleFrom(
                    foregroundColor: hasSelection ? p.purple : p.text2,
                    disabledForegroundColor: p.text2,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Удалить',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Список чатов с совпадениями → drill-down в файлы/медиа чата.
class _GlobalMediaSearchBody extends StatefulWidget {
  final List<GlobalSearchChatGroup> groups;
  final GlobalSearchScope scope;
  final String searchQuery;
  final String? preloadLabel;
  final bool preloading;
  final String? selectedId;
  final String? activeHitKey;
  final void Function(GlobalSearchHit hit) onOpenHit;

  const _GlobalMediaSearchBody({
    required this.groups,
    required this.scope,
    required this.searchQuery,
    required this.preloadLabel,
    required this.preloading,
    required this.selectedId,
    required this.activeHitKey,
    required this.onOpenHit,
  });

  @override
  State<_GlobalMediaSearchBody> createState() => _GlobalMediaSearchBodyState();
}

class _GlobalMediaSearchBodyState extends State<_GlobalMediaSearchBody> {
  String? _openedDialogId;

  @override
  void didUpdateWidget(covariant _GlobalMediaSearchBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.scope != widget.scope) {
      _openedDialogId = null;
      return;
    }
    if (_openedDialogId != null &&
        !widget.groups.any((g) => g.dialogId == _openedDialogId)) {
      _openedDialogId = null;
    }
  }

  GlobalSearchChatGroup? get _openedGroup {
    final id = _openedDialogId;
    if (id == null) return null;
    for (final g in widget.groups) {
      if (g.dialogId == id) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final opened = _openedGroup;

    if (widget.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.preloading) ...[
              CircularProgressIndicator(color: p.purple, strokeWidth: 2),
              const SizedBox(height: 16),
            ],
            Text(
              widget.preloadLabel ?? 'Ничего не найдено',
              style: TextStyle(color: p.text2, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (widget.preloadLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: p.purple,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.preloadLabel!,
                    style: TextStyle(color: p.text2, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (opened != null)
          _ChatDrillHeader(
            dialog: opened.dialog,
            countLabel: opened.countLabel(widget.scope),
            onBack: () => setState(() => _openedDialogId = null),
          ),
        Expanded(
          child: opened == null
              ? _GlobalSearchChatsList(
                  groups: widget.groups,
                  selectedId: widget.selectedId,
                  onOpenChat: (group) {
                    setState(() => _openedDialogId = group.dialogId);
                  },
                )
              : _GlobalSearchHitsList(
                  hits: opened.hits,
                  activeHitKey: widget.activeHitKey,
                  onOpen: widget.onOpenHit,
                ),
        ),
      ],
    );
  }
}

class _ChatDrillHeader extends StatelessWidget {
  final DialogsListViewModel dialog;
  final String countLabel;
  final VoidCallback onBack;

  const _ChatDrillHeader({
    required this.dialog,
    required this.countLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.bg2,
      child: InkWell(
        onTap: onBack,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Назад к чатам',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_rounded, color: p.text1, size: 22),
              ),
              AvatarWidget(
                name: dialog.chatName,
                avatarUrl: dialog.avatar,
                avatarColor: dialog.avatarColor,
                colAvaId: dialog.colAvaId,
                online: dialog.online,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialog.chatName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text2, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchChatsList extends StatefulWidget {
  final List<GlobalSearchChatGroup> groups;
  final String? selectedId;
  final void Function(GlobalSearchChatGroup group) onOpenChat;

  const _GlobalSearchChatsList({
    required this.groups,
    required this.selectedId,
    required this.onOpenChat,
  });

  @override
  State<_GlobalSearchChatsList> createState() => _GlobalSearchChatsListState();
}

class _GlobalSearchChatsListState extends State<_GlobalSearchChatsList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _controller,
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: widget.groups.length,
        itemBuilder: (context, index) {
          final group = widget.groups[index];
          final selected = group.dialog.id == widget.selectedId;
          return _GlobalSearchChatTile(
            group: group,
            selected: selected,
            onTap: () => widget.onOpenChat(group),
          );
        },
      ),
    );
  }
}

class _GlobalSearchChatTile extends StatelessWidget {
  final GlobalSearchChatGroup group;
  final bool selected;
  final VoidCallback onTap;

  const _GlobalSearchChatTile({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dialog = group.dialog;
    final latest = group.hits.first;
    final titleColor = selected ? Colors.white : p.text1;
    final subColor = selected ? Colors.white70 : p.text2;
    final bg = selected ? p.selectedTile : Colors.transparent;

    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: ColoredBox(
        color: bg,
        child: SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                AvatarWidget(
                  name: dialog.chatName,
                  avatarUrl: dialog.avatar,
                  avatarColor: dialog.avatarColor,
                  colAvaId: dialog.colAvaId,
                  online: dialog.online,
                  size: 52,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dialog.chatName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        latest.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subColor, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (latest.message.dtshow.isNotEmpty)
                      Text(
                        latest.message.dtshow,
                        style: TextStyle(color: subColor, fontSize: 12),
                      ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (selected ? Colors.white : p.purple)
                            .withValues(alpha: selected ? 0.25 : 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${group.count}',
                        style: TextStyle(
                          color: selected ? Colors.white : p.purple,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchHitsList extends StatefulWidget {
  final List<GlobalSearchHit> hits;
  final String? activeHitKey;
  final void Function(GlobalSearchHit hit) onOpen;

  const _GlobalSearchHitsList({
    required this.hits,
    required this.activeHitKey,
    required this.onOpen,
  });

  @override
  State<_GlobalSearchHitsList> createState() => _GlobalSearchHitsListState();
}

class _GlobalSearchHitsListState extends State<_GlobalSearchHitsList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _controller,
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: widget.hits.length,
        itemBuilder: (context, index) {
          final hit = widget.hits[index];
          final selected = hit.selectionKey == widget.activeHitKey;
          return GlobalSearchHitTile(
            hit: hit,
            selected: selected,
            onTap: () => widget.onOpen(hit),
            hideChatInSubtitle: true,
          );
        },
      ),
    );
  }
}

class _DialogsScrollList extends StatefulWidget {
  final List<DialogsListViewModel> dialogs;
  final String? selectedId;
  final String? hoverId;
  final bool selectMode;
  final void Function(String? id) onSelect;

  const _DialogsScrollList({
    required this.dialogs,
    required this.selectedId,
    required this.hoverId,
    required this.onSelect,
    this.selectMode = false,
  });

  @override
  State<_DialogsScrollList> createState() => _DialogsScrollListState();
}

class _DialogsScrollListState extends State<_DialogsScrollList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView.builder(
      controller: _controller,
      primary: false,
      padding: EdgeInsets.zero,
      itemCount: widget.dialogs.length,
      itemBuilder: (context, index) {
        final d = widget.dialogs[index];
        final id = d.id?.trim() ?? '';
        final selected =
            !widget.selectMode &&
            widget.hoverId == null &&
            d.id == widget.selectedId;
        final tile = DialogTile(
          dialog: d,
          selected: selected,
          dropHover: !widget.selectMode &&
              widget.hoverId != null &&
              widget.hoverId == id,
          selectMode: widget.selectMode,
          checked: widget.selectMode && app.isDialogChecked(d.id),
          onTap: () => widget.onSelect(d.id),
        );
        if (id.isEmpty || widget.selectMode) return tile;
        return DialogDropTarget(
          dlgId: id,
          child: tile,
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: p.text1, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}
