import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/chat_file_dnd.dart';

/// Приём файлов (в т.ч. группы) из Finder/Explorer в открытый диалог.
class ChatDropTarget extends StatefulWidget {
  final Widget child;

  const ChatDropTarget({super.key, required this.child});

  @override
  State<ChatDropTarget> createState() => _ChatDropTargetState();
}

class _ChatDropTargetState extends State<ChatDropTarget> {
  bool _over = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!ChatFileDnd.isSupported) return widget.child;

    final p = context.palette;

    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.translucent,
      onDropOver: (event) {
        // Игнор внутренних перетаскиваний вложений чата.
        final onlyOwn = event.session.items.every(
          (item) => ChatFileDnd.isOwnAttachmentLocalData(item.localData),
        );
        if (onlyOwn) return DropOperation.none;

        final allowed = event.session.allowedOperations;
        if (allowed.contains(DropOperation.copy)) {
          if (!_over) setState(() => _over = true);
          return DropOperation.copy;
        }
        if (allowed.contains(DropOperation.link)) {
          if (!_over) setState(() => _over = true);
          return DropOperation.link;
        }
        return DropOperation.none;
      },
      onDropLeave: (_) {
        if (_over) setState(() => _over = false);
      },
      onDropEnded: (_) {
        if (_over) setState(() => _over = false);
      },
      onPerformDrop: (event) async {
        if (_busy) return;
        setState(() {
          _busy = true;
          _over = false;
        });
        final appState = context.read<AppState>();
        final messenger = ScaffoldMessenger.of(context);
        try {
          final files = await ChatFileDnd.readDroppedFiles(event.session);
          if (!mounted || files.isEmpty) return;
          await appState.sendDroppedAttachments(files);
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Не удалось отправить файлы: $e')),
          );
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_over || _busy)
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                color: p.purple.withValues(alpha: _busy ? 0.10 : 0.18),
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: p.bg2.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.purple, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.purple,
                          ),
                        )
                      else
                        Icon(Icons.file_download_outlined,
                            color: p.purple, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        _busy
                            ? 'Отправка…'
                            : 'Отпустите, чтобы отправить в чат',
                        style: TextStyle(
                          color: p.text1,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
