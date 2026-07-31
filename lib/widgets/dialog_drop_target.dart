import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../state/app_state.dart';
import '../utils/chat_file_dnd.dart';

/// Какой чат сейчас под курсором при DnD файлов (не больше одного).
class DialogDropHover {
  DialogDropHover._();

  static final ValueNotifier<String?> id = ValueNotifier<String?>(null);

  static void set(String? value) {
    if (id.value == value) return;
    id.value = value;
  }

  static void clearIf(String dlgId) {
    if (id.value == dlgId) id.value = null;
  }

  static void clear() => set(null);
}

/// Drop на строку чата в списке:
/// — подсветка только этого чата (предыдущее выделение снимается);
/// — через 1 с удержания открывается диалог;
/// — drop отправляет файлы в этот чат.
class DialogDropTarget extends StatefulWidget {
  final String dlgId;
  final Widget child;

  const DialogDropTarget({
    super.key,
    required this.dlgId,
    required this.child,
  });

  @override
  State<DialogDropTarget> createState() => _DialogDropTargetState();
}

class _DialogDropTargetState extends State<DialogDropTarget> {
  static const _openDelay = Duration(seconds: 1);

  bool _busy = false;
  Timer? _openTimer;

  @override
  void dispose() {
    _cancelOpenTimer();
    DialogDropHover.clearIf(widget.dlgId);
    super.dispose();
  }

  void _cancelOpenTimer() {
    _openTimer?.cancel();
    _openTimer = null;
  }

  void _enterHover() {
    DialogDropHover.set(widget.dlgId);
    _scheduleOpen();
  }

  void _leaveHover() {
    _cancelOpenTimer();
    DialogDropHover.clearIf(widget.dlgId);
  }

  void _scheduleOpen() {
    _cancelOpenTimer();
    final dlgId = widget.dlgId;
    _openTimer = Timer(_openDelay, () {
      if (!mounted) return;
      if (DialogDropHover.id.value != dlgId) return;
      final state = context.read<AppState>();
      if (state.selectedId == dlgId) return;
      unawaited(state.selectDialog(dlgId));
    });
  }

  DropOperation _acceptIfExternal(DropOverEvent event) {
    final onlyOwn = event.session.items.every(
      (item) => ChatFileDnd.isOwnAttachmentLocalData(item.localData),
    );
    if (onlyOwn) return DropOperation.none;

    final allowed = event.session.allowedOperations;
    if (allowed.contains(DropOperation.copy)) return DropOperation.copy;
    if (allowed.contains(DropOperation.link)) return DropOperation.link;
    return DropOperation.none;
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatFileDnd.isSupported) return widget.child;

    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: (_) => _enterHover(),
      onDropOver: (event) {
        final op = _acceptIfExternal(event);
        if (op != DropOperation.none) {
          if (DialogDropHover.id.value != widget.dlgId) {
            _enterHover();
          }
        }
        return op;
      },
      onDropLeave: (_) => _leaveHover(),
      onDropEnded: (_) {
        _cancelOpenTimer();
        DialogDropHover.clear();
      },
      onPerformDrop: (event) async {
        if (_busy) return;
        _cancelOpenTimer();
        DialogDropHover.clear();
        setState(() => _busy = true);
        final appState = context.read<AppState>();
        final messenger = ScaffoldMessenger.maybeOf(context);
        try {
          final files = await ChatFileDnd.readDroppedFiles(event.session);
          if (!mounted || files.isEmpty) return;
          await appState.sendDroppedAttachments(
            files,
            dlgId: widget.dlgId,
          );
        } catch (e) {
          if (!mounted) return;
          messenger?.showSnackBar(
            SnackBar(content: Text('Не удалось отправить файлы: $e')),
          );
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
      child: widget.child,
    );
  }
}
