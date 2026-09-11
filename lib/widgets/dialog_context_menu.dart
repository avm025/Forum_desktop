import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_type.dart';
import '../models/dialog_group.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'folder_name_dialog.dart';

/// Контекстное меню чата (ПКМ) в раскладке Telegram Desktop.
class DialogContextMenu {
  DialogContextMenu._();

  static OverlayEntry? _entry;

  static void close() {
    _entry?.remove();
    _entry = null;
  }

  static Future<void> show({
    required BuildContext context,
    required Offset globalPosition,
    required DialogsListViewModel dialog,
  }) async {
    final dlgId = dialog.id?.trim() ?? '';
    if (dlgId.isEmpty || DialogsListViewModel.isPlaceholderDlgId(dlgId)) {
      return;
    }

    close();
    final completer = Completer<_MenuAction?>();

    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _MenuOverlay(
          anchor: globalPosition,
          dialog: dialog,
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
    if (action == null || !context.mounted) return;
    await _handle(context, dialog, action);
  }

  static Future<void> _handle(
    BuildContext context,
    DialogsListViewModel dialog,
    _MenuAction action,
  ) async {
    final app = context.read<AppState>();
    final dlgId = dialog.id?.trim() ?? '';
    if (dlgId.isEmpty) return;

    switch (action.kind) {
      case _MenuKind.openWindow:
        await _showChatWindow(context, dialog);
      case _MenuKind.pin:
        await app.setDialogPinned(dlgId, pinned: !dialog.isPinned);
      case _MenuKind.muteOff:
        app.setDialogMuted(dlgId, muted: false);
      case _MenuKind.muteHour:
        app.setDialogMuted(
          dlgId,
          muted: true,
          until: DateTime.now().add(const Duration(hours: 1)),
        );
      case _MenuKind.muteHours8:
        app.setDialogMuted(
          dlgId,
          muted: true,
          until: DateTime.now().add(const Duration(hours: 8)),
        );
      case _MenuKind.muteDays2:
        app.setDialogMuted(
          dlgId,
          muted: true,
          until: DateTime.now().add(const Duration(days: 2)),
        );
      case _MenuKind.muteForever:
        app.setDialogMuted(dlgId, muted: true);
      case _MenuKind.unread:
        if (dialog.unread > 0) {
          app.markDialogRead(dlgId);
        } else {
          app.markDialogUnread(dlgId);
        }
      case _MenuKind.preview:
        await _showPreview(context, dialog);
      case _MenuKind.archive:
        app.setDialogArchived(dlgId, archived: !app.isDialogArchived(dlgId));
      case _MenuKind.folderToggle:
        final folderId = action.payload ?? '';
        if (folderId.isEmpty) return;
        if (app.connectionStatus != ConnectionStatus.connected) {
          _snack(context, 'Нет подключения к серверу');
          return;
        }
        try {
          await app.toggleDialogInFolder(folderId: folderId, dlgId: dlgId);
        } catch (e) {
          if (context.mounted) _snack(context, 'Не удалось обновить папку: $e');
        }
      case _MenuKind.folderCreate:
        if (!context.mounted) return;
        if (app.connectionStatus != ConnectionStatus.connected) {
          _snack(context, 'Нет подключения к серверу');
          return;
        }
        final name = await showFolderNameDialog(
          context,
          title: 'Название папки',
          confirmLabel: 'Создать',
        );
        if (name == null || !context.mounted) return;
        try {
          await context.read<AppState>().createFolder(
                name: name,
                dialogIds: [dlgId],
                selectAfterCreate: false,
              );
        } catch (e) {
          if (context.mounted) _snack(context, 'Не удалось создать папку: $e');
        }
      case _MenuKind.clearHistory:
        final ok = await _confirm(
          context,
          title: 'Очистить историю?',
          body: 'Все сообщения в этом чате будут удалены.',
          confirm: 'Очистить',
        );
        if (ok && context.mounted) {
          await context.read<AppState>().clearDialogHistory(dlgId);
        }
      case _MenuKind.delete:
        final ok = await _confirm(
          context,
          title: 'Удалить чат?',
          body: 'Чат будет удалён из списка.',
          confirm: 'Удалить',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        try {
          await context.read<AppState>().deleteDialog(dlgId);
        } catch (e) {
          if (context.mounted) {
            _snack(context, e.toString().replaceFirst('Bad state: ', ''));
          }
        }
      case _MenuKind.leaveGroup:
        final ok = await _confirm(
          context,
          title: 'Покинуть группу?',
          body: 'Вы выйдете из группы «${dialog.chatName}».',
          confirm: 'Покинуть',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        try {
          await context.read<AppState>().leaveGroup(dlgId);
        } catch (e) {
          if (context.mounted) {
            _snack(context, e.toString().replaceFirst('Bad state: ', ''));
          }
        }
    }
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirm,
    bool destructive = false,
  }) async {
    final p = context.palette;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: p.bg2,
          surfaceTintColor: Colors.transparent,
          title: Text(title, style: TextStyle(color: p.text1)),
          content: Text(body, style: TextStyle(color: p.text2)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Отмена', style: TextStyle(color: p.text2)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                confirm,
                style: TextStyle(
                  color: destructive ? const Color(0xFFE53935) : p.purple,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> _showPreview(
    BuildContext context,
    DialogsListViewModel dialog,
  ) {
    return _showPeek(context, dialog, compact: true);
  }

  static Future<void> _showChatWindow(
    BuildContext context,
    DialogsListViewModel dialog,
  ) {
    return _showPeek(context, dialog, compact: false);
  }

  static Future<void> _showPeek(
    BuildContext context,
    DialogsListViewModel dialog, {
    required bool compact,
  }) {
    final id = dialog.id?.trim() ?? '';
    if (id.isNotEmpty) {
      unawaited(context.read<AppState>().loadMessages(id));
    }
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: compact ? 0.35 : 0.28),
      builder: (ctx) => _ChatPeekDialog(dialog: dialog, compact: compact),
    );
  }
}

enum _MenuKind {
  openWindow,
  pin,
  muteOff,
  muteHour,
  muteHours8,
  muteDays2,
  muteForever,
  unread,
  preview,
  archive,
  folderToggle,
  folderCreate,
  clearHistory,
  delete,
  leaveGroup,
}

class _MenuAction {
  final _MenuKind kind;
  final String? payload;

  const _MenuAction(this.kind, [this.payload]);
}

class _MenuOverlay extends StatefulWidget {
  final Offset anchor;
  final DialogsListViewModel dialog;
  final void Function(_MenuAction action) onPick;
  final VoidCallback onDismiss;

  const _MenuOverlay({
    required this.anchor,
    required this.dialog,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay> {
  static const _width = 268.0;
  static const _subWidth = 220.0;
  static const _radius = 12.0;

  String? _submenu;
  Timer? _subClose;

  @override
  void dispose() {
    _subClose?.cancel();
    super.dispose();
  }

  void _openSub(String id) {
    _subClose?.cancel();
    if (_submenu == id) return;
    setState(() => _submenu = id);
  }

  void _keepSub() => _subClose?.cancel();

  void _closeSubSoon() {
    _subClose?.cancel();
    _subClose = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() => _submenu = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.watch<AppState>();
    final dialog = widget.dialog;
    final dlgId = dialog.id ?? '';
    final archived = app.isDialogArchived(dlgId);
    final folders = app.groups;

    final screen = MediaQuery.sizeOf(context);
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlayBox.globalToLocal(widget.anchor);

    final items = _items(dialog, archived: archived);
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

    final subOnLeft = left + _width + _subWidth + 8 > screen.width;
    final subLeft = subOnLeft ? left - _subWidth - 4 : left + _width + 4;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            onSecondaryTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: _Card(
            palette: p,
            radius: _radius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++)
                  if (items[i].divider)
                    _Divider(color: p.border1)
                  else
                    _Row(
                      item: items[i],
                      palette: p,
                      hovered: _submenu == items[i].submenu,
                      onHover: (inside) {
                        if (items[i].submenu == null) {
                          if (inside) _closeSubSoon();
                          return;
                        }
                        if (inside) {
                          _openSub(items[i].submenu!);
                        } else {
                          _closeSubSoon();
                        }
                      },
                      onTap: items[i].action == null
                          ? null
                          : () => widget.onPick(items[i].action!),
                    ),
              ],
            ),
          ),
        ),
        if (_submenu == 'mute')
          Positioned(
            left: subLeft.clamp(8.0, math.max(8.0, screen.width - _subWidth - 8)),
            top: top + _submenuTop(items, 'mute'),
            width: _subWidth,
            child: MouseRegion(
              onEnter: (_) => _keepSub(),
              onExit: (_) => _closeSubSoon(),
              child: _Card(
              palette: p,
              radius: _radius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dialog.chatMuted)
                    _Row(
                      item: const _Item(
                        icon: Icons.notifications_outlined,
                        label: 'Включить уведомления',
                        action: _MenuAction(_MenuKind.muteOff),
                      ),
                      palette: p,
                      onTap: () => widget.onPick(
                        const _MenuAction(_MenuKind.muteOff),
                      ),
                    ),
                  _Row(
                    item: const _Item(
                      icon: Icons.schedule_outlined,
                      label: 'На 1 час',
                      action: _MenuAction(_MenuKind.muteHour),
                    ),
                    palette: p,
                    onTap: () => widget.onPick(
                      const _MenuAction(_MenuKind.muteHour),
                    ),
                  ),
                  _Row(
                    item: const _Item(
                      icon: Icons.schedule_outlined,
                      label: 'На 8 часов',
                      action: _MenuAction(_MenuKind.muteHours8),
                    ),
                    palette: p,
                    onTap: () => widget.onPick(
                      const _MenuAction(_MenuKind.muteHours8),
                    ),
                  ),
                  _Row(
                    item: const _Item(
                      icon: Icons.calendar_today_outlined,
                      label: 'На 2 дня',
                      action: _MenuAction(_MenuKind.muteDays2),
                    ),
                    palette: p,
                    onTap: () => widget.onPick(
                      const _MenuAction(_MenuKind.muteDays2),
                    ),
                  ),
                  _Row(
                    item: const _Item(
                      icon: Icons.notifications_off_outlined,
                      label: 'Навсегда',
                      action: _MenuAction(_MenuKind.muteForever),
                    ),
                    palette: p,
                    onTap: () => widget.onPick(
                      const _MenuAction(_MenuKind.muteForever),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        if (_submenu == 'folder')
          Positioned(
            left: subLeft.clamp(8.0, math.max(8.0, screen.width - _subWidth - 8)),
            top: top + _submenuTop(items, 'folder'),
            width: _subWidth,
            child: MouseRegion(
              onEnter: (_) => _keepSub(),
              onExit: (_) => _closeSubSoon(),
              child: _Card(
              palette: p,
              radius: _radius,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(320, screen.height - 24),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final folder in folders)
                        _Row(
                          item: _Item(
                            icon: Icons.folder_outlined,
                            label: folder.name.trim().isEmpty
                                ? 'Папка'
                                : folder.name.trim(),
                            trailing: _folderHas(folder, dlgId)
                                ? Icons.check
                                : null,
                            action: _MenuAction(
                              _MenuKind.folderToggle,
                              folder.id,
                            ),
                          ),
                          palette: p,
                          onTap: () => widget.onPick(
                            _MenuAction(_MenuKind.folderToggle, folder.id),
                          ),
                        ),
                      if (folders.isNotEmpty) _Divider(color: p.border1),
                      _Row(
                        item: const _Item(
                          icon: Icons.create_new_folder_outlined,
                          label: 'Создать папку…',
                          action: _MenuAction(_MenuKind.folderCreate),
                        ),
                        palette: p,
                        onTap: () => widget.onPick(
                          const _MenuAction(_MenuKind.folderCreate),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }

  List<_Item> _items(DialogsListViewModel dialog, {required bool archived}) {
    return [
      const _Item(
        icon: Icons.open_in_new_rounded,
        label: 'Открыть в отдельном окне',
        action: _MenuAction(_MenuKind.openWindow),
      ),
      _Item(
        icon: dialog.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: dialog.isPinned ? 'Открепить' : 'Закрепить',
        action: const _MenuAction(_MenuKind.pin),
      ),
      _Item(
        icon: dialog.chatMuted
            ? Icons.notifications_outlined
            : Icons.notifications_off_outlined,
        label: dialog.chatMuted
            ? 'Включить уведомления'
            : 'Выключить уведомления',
        chevron: true,
        submenu: 'mute',
        action: dialog.chatMuted
            ? const _MenuAction(_MenuKind.muteOff)
            : const _MenuAction(_MenuKind.muteForever),
      ),
      _Item(
        icon: dialog.unread > 0
            ? Icons.mark_chat_read_outlined
            : Icons.mark_chat_unread_outlined,
        label: dialog.unread > 0
            ? 'Пометить как прочитанное'
            : 'Пометить как непрочитанное',
        action: const _MenuAction(_MenuKind.unread),
      ),
      const _Item(
        icon: Icons.visibility_outlined,
        label: 'Предпросмотр',
        action: _MenuAction(_MenuKind.preview),
      ),
      const _Item(divider: true),
      _Item(
        icon: Icons.inventory_2_outlined,
        label: archived ? 'Разархивировать' : 'В архив',
        action: const _MenuAction(_MenuKind.archive),
      ),
      const _Item(
        icon: Icons.create_new_folder_outlined,
        label: 'Добавить в папку…',
        chevron: true,
        submenu: 'folder',
      ),
      const _Item(divider: true),
      const _Item(
        icon: Icons.highlight_off_outlined,
        label: 'Очистить историю',
        action: _MenuAction(_MenuKind.clearHistory),
      ),
      if (dialog.isGrp || dialog.chatType == ChatType.groupChat)
        const _Item(
          // Как в Telegram: дверь со стрелкой «выйти».
          icon: Icons.logout_rounded,
          label: 'Покинуть группу',
          destructive: true,
          action: _MenuAction(_MenuKind.leaveGroup),
        )
      else
        const _Item(
          icon: Icons.delete_outline,
          label: 'Удалить чат',
          destructive: true,
          action: _MenuAction(_MenuKind.delete),
        ),
    ];
  }

  double _estimateHeight(List<_Item> items) {
    var h = 8.0;
    for (final item in items) {
      h += item.divider ? 9 : 36;
    }
    return h;
  }

  double _submenuTop(List<_Item> items, String id) {
    var y = 4.0;
    for (final item in items) {
      if (item.submenu == id) return y;
      y += item.divider ? 9 : 36;
    }
    return y;
  }

  bool _folderHas(DialogGroup folder, String dlgId) {
    return folder.dialogIds.any((id) => AppState.sameDlgId(id, dlgId));
  }
}

class _Item {
  final IconData icon;
  final String label;
  final bool chevron;
  final bool destructive;
  final bool divider;
  final String? submenu;
  final IconData? trailing;
  final _MenuAction? action;

  const _Item({
    this.icon = Icons.circle,
    this.label = '',
    this.chevron = false,
    this.destructive = false,
    this.divider = false,
    this.submenu,
    this.trailing,
    this.action,
  });
}

class _Card extends StatelessWidget {
  final ForumPalette palette;
  final double radius;
  final Widget child;

  const _Card({
    required this.palette,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bg2,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: palette.border1.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;

  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(height: 1, thickness: 1, color: color.withValues(alpha: 0.7)),
    );
  }
}

class _Row extends StatefulWidget {
  final _Item item;
  final ForumPalette palette;
  final bool hovered;
  final void Function(bool inside)? onHover;
  final VoidCallback? onTap;

  const _Row({
    required this.item,
    required this.palette,
    this.hovered = false,
    this.onHover,
    this.onTap,
  });

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final active = _hover || widget.hovered;
    final color = widget.item.destructive
        ? const Color(0xFFE53935)
        : p.text1;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onHover?.call(true);
      },
      onExit: (_) {
        setState(() => _hover = false);
        widget.onHover?.call(false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: active ? p.bg3 : Colors.transparent,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(widget.item.icon, size: 18, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.item.trailing != null)
                    Icon(widget.item.trailing, size: 16, color: p.text2),
                  if (widget.item.chevron)
                    Icon(Icons.chevron_right, size: 18, color: p.text2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatPeekDialog extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool compact;

  const _ChatPeekDialog({
    required this.dialog,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = compact ? 340.0 : 440.0;
    final height = compact ? 360.0 : 520.0;
    final live = context.select<AppState, DialogsListViewModel?>((s) {
      for (final d in s.allDialogs) {
        if (AppState.sameDlgId(d.id, dialog.id)) return d;
      }
      return dialog;
    });
    final current = live ?? dialog;
    final messages = current.messages.length > 40
        ? current.messages.sublist(current.messages.length - 40)
        : current.messages;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        child: Material(
          color: p.bg2,
          elevation: 18,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      AvatarWidget(
                        name: current.chatName,
                        avatarUrl: current.avatar,
                        avatarColor: current.avatarColor,
                        colAvaId: current.colAvaId,
                        online: current.online,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          current.chatName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: p.text2),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: p.border1),
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Text(
                          current.last_msg.trim().isEmpty
                              ? 'Нет сообщений'
                              : current.last_msg,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.text2, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return _PeekMessage(
                            message: messages[index],
                            palette: p,
                          );
                        },
                      ),
              ),
              Divider(height: 1, color: p.border1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      final id = current.id;
                      Navigator.of(context).pop();
                      if (id != null) {
                        context.read<AppState>().selectDialog(id);
                      }
                    },
                    child: Text(
                      'Открыть чат',
                      style: TextStyle(color: p.purple, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeekMessage extends StatelessWidget {
  final MessageViewModel message;
  final ForumPalette palette;

  const _PeekMessage({
    required this.message,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final text = message.body.trim().isNotEmpty
        ? message.body
        : (message.text.trim().isNotEmpty ? message.text : message.preview);
    final label = text.trim().isEmpty ? 'Вложение' : text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            message.my ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!message.my && message.fr_name.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                message.fr_name,
                style: TextStyle(
                  color: palette.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: message.my ? palette.outgoingBubble : palette.bg3,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: message.my ? Colors.white : palette.text1,
                fontSize: 13,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
