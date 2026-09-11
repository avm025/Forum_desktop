import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/forum_api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'delete_folder_dialog.dart';
import 'folder_chat_picker.dart';
import 'folder_name_dialog.dart';
import 'folder_sort_screen.dart';

/// Контекстное меню вкладки папки (ПКМ, стиль как у меню чата).
class FolderActions {
  FolderActions._();

  static OverlayEntry? _entry;

  static void close() {
    _entry?.remove();
    _entry = null;
  }

  static Future<void> showTabMenu(
    BuildContext context, {
    required String tabId,
    required String label,
    required Offset globalPosition,
  }) async {
    close();
    final state = context.read<AppState>();
    final isUser = state.isUserFolderTab(tabId);
    final completer = Completer<String?>();

    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _FolderMenuOverlay(
          anchor: globalPosition,
          isUserFolder: isUser,
          onPick: (action) {
            if (!completer.isCompleted) completer.complete(action);
            close();
          },
          onDismiss: () {
            if (!completer.isCompleted) completer.complete(null);
            close();
          },
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);

    final action = await completer.future;
    if (!context.mounted || action == null) return;

    switch (action) {
      case 'rename':
        await _rename(context, tabId, label);
      case 'chats':
        await _editChats(context, tabId);
      case 'sort':
        await FolderSortScreen.open(context);
      case 'delete':
        await _delete(context, tabId);
    }
  }

  static Future<void> _rename(
    BuildContext context,
    String tabId,
    String currentName,
  ) async {
    final name = await showFolderNameDialog(
      context,
      title: 'Изменить имя',
      initialName: currentName,
    );
    if (name == null || !context.mounted) return;

    try {
      await context.read<AppState>().renameFolder(id: tabId, name: name);
    } on ForumApiException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  static Future<void> _editChats(BuildContext context, String tabId) async {
    final group = context.read<AppState>().groupById(tabId);
    if (group == null) return;

    await FolderChatPicker.openEdit(
      context,
      folderId: tabId,
      initialSelected: group.dialogIds,
    );
  }

  static Future<void> _delete(BuildContext context, String tabId) async {
    final confirmed = await showDeleteFolderDialog(context);
    if (!confirmed || !context.mounted) return;

    try {
      await context.read<AppState>().deleteFolder(tabId);
    } on ForumApiException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _FolderMenuOverlay extends StatelessWidget {
  static const _width = 268.0;
  static const _radius = 12.0;

  final Offset anchor;
  final bool isUserFolder;
  final void Function(String action) onPick;
  final VoidCallback onDismiss;

  const _FolderMenuOverlay({
    required this.anchor,
    required this.isUserFolder,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = _items();
    final screen = MediaQuery.sizeOf(context);
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlayBox.globalToLocal(anchor);

    final menuHeight = _estimateHeight(items);
    var left = local.dx;
    var top = local.dy;
    if (left + _width > screen.width - 8) {
      left = screen.width - _width - 8;
    }
    if (top + menuHeight > screen.height - 8) {
      top = screen.height - menuHeight - 8;
    }
    left = left.clamp(8.0, math.max(8.0, screen.width - _width - 8));
    top = top.clamp(8.0, math.max(8.0, screen.height - menuHeight - 8));

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: Material(
            color: p.bg2,
            elevation: 16,
            shadowColor: Colors.black.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
              side: BorderSide(color: p.border1.withValues(alpha: 0.7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    if (item.divider)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: p.border1.withValues(alpha: 0.7),
                        ),
                      )
                    else
                      _FolderMenuRow(
                        icon: item.icon,
                        label: item.label,
                        destructive: item.destructive,
                        palette: p,
                        onTap: () => onPick(item.id!),
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<_FolderMenuItem> _items() {
    return [
      if (isUserFolder) ...[
        const _FolderMenuItem(
          id: 'rename',
          icon: Icons.edit_outlined,
          label: 'Изменить имя',
        ),
        const _FolderMenuItem(
          id: 'chats',
          icon: Icons.person_add_alt_1_outlined,
          label: 'Добавить чаты',
        ),
      ],
      const _FolderMenuItem(
        id: 'sort',
        icon: Icons.swap_vert_rounded,
        label: 'Изменить порядок',
      ),
      if (isUserFolder) ...[
        const _FolderMenuItem(divider: true),
        const _FolderMenuItem(
          id: 'delete',
          icon: Icons.delete_outline,
          label: 'Удалить',
          destructive: true,
        ),
      ],
    ];
  }

  double _estimateHeight(List<_FolderMenuItem> items) {
    var h = 8.0;
    for (final item in items) {
      h += item.divider ? 9 : 36;
    }
    return h;
  }
}

class _FolderMenuItem {
  final String? id;
  final IconData icon;
  final String label;
  final bool destructive;
  final bool divider;

  const _FolderMenuItem({
    this.id,
    this.icon = Icons.circle,
    this.label = '',
    this.destructive = false,
    this.divider = false,
  });
}

class _FolderMenuRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final ForumPalette palette;
  final VoidCallback onTap;

  const _FolderMenuRow({
    required this.icon,
    required this.label,
    required this.destructive,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_FolderMenuRow> createState() => _FolderMenuRowState();
}

class _FolderMenuRowState extends State<_FolderMenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final color =
        widget.destructive ? const Color(0xFFE53935) : p.text1;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: _hover ? p.bg3 : Colors.transparent,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
