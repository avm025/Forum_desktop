import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../models/media_file.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/chat_file_dnd.dart';
import '../utils/media_file_loader.dart';

extension on DragSession {
  Future<bool> hasLocalData(Object data) async {
    final localData = await getLocalData() ?? [];
    return localData.contains(data);
  }
}

/// Обёртка вложений: одиночный файл или вся выделенная группа.
class DraggableAttachmentGroup extends StatefulWidget {
  final List<MediaFile> files;

  /// Id выделенных файлов (см. [fileId]). Если тянут выделенный —
  /// в сессию попадают все выделенные; иначе только один.
  final Set<String> selectedIds;

  /// Можно ли начать DnD с этого файла (глобальные координаты не нужны —
  /// проверка по id файла под виджетом).
  final bool Function(String fileId)? canStartDrag;

  /// В превью перетаскивания только имя файла (без иконок/кнопок строки).
  final bool nameOnlyDragPreview;

  final Widget Function(
    BuildContext context,
    Widget Function(MediaFile file, Widget child) wrapFile,
  ) builder;

  const DraggableAttachmentGroup({
    super.key,
    required this.files,
    required this.builder,
    this.selectedIds = const {},
    this.canStartDrag,
    this.nameOnlyDragPreview = false,
  });

  static String fileId(MediaFile file, int index) {
    if (file.hash.isNotEmpty) return file.hash;
    if (file.fname.isNotEmpty) return '${file.fname}_$index';
    return 'file_$index';
  }

  @override
  State<DraggableAttachmentGroup> createState() =>
      _DraggableAttachmentGroupState();
}

class _DraggableAttachmentGroupState extends State<DraggableAttachmentGroup> {
  final Map<String, GlobalKey<DragItemWidgetState>> _keys = {};

  List<DragItemWidgetState> _statesForDrag(String startedId) {
    final selected = widget.selectedIds;
    final ids = (selected.contains(startedId) && selected.length > 1)
        ? selected
        : {startedId};

    return ids
        .map((id) => _keys[id]?.currentState)
        .whereType<DragItemWidgetState>()
        .toList(growable: false);
  }

  Widget _namePreview(BuildContext context, MediaFile file) {
    final p = context.palette;
    final name = MediaFileLoader.displayFileName(file);
    return Material(
      color: p.bg2,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.text1,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatFileDnd.isSupported || widget.files.isEmpty) {
      return widget.builder(context, (_, child) => child);
    }

    final next = <String, GlobalKey<DragItemWidgetState>>{};
    for (var i = 0; i < widget.files.length; i++) {
      final id = DraggableAttachmentGroup.fileId(widget.files[i], i);
      next[id] = _keys[id] ?? GlobalKey<DragItemWidgetState>();
    }
    _keys
      ..clear()
      ..addAll(next);

    return widget.builder(context, (file, child) {
      final index = widget.files.indexOf(file);
      final id = DraggableAttachmentGroup.fileId(file, index < 0 ? 0 : index);
      final key = _keys.putIfAbsent(id, GlobalKey<DragItemWidgetState>.new);
      final localId = 'forum-file-$id';

      return DragItemWidget(
        key: key,
        allowedOperations: () => [DropOperation.copy],
        canAddItemToExistingSession: true,
        liftBuilder: widget.nameOnlyDragPreview
            ? (context, _) => _namePreview(context, file)
            : null,
        dragBuilder: widget.nameOnlyDragPreview
            ? (context, _) => _namePreview(context, file)
            : null,
        dragItemProvider: (request) async {
          if (await request.session.hasLocalData(localId)) {
            return null;
          }
          final item =
              await ChatFileDnd.buildDragItem(file, localId: localId);
          if (item == null) return null;

          void onDraggingChanged() {
            if (!request.session.dragging.value) {
              request.session.dragging.removeListener(onDraggingChanged);
              AttachmentSelection.clear();
            }
          }

          request.session.dragging.addListener(onDraggingChanged);
          return item;
        },
        child: DraggableWidget(
          isLocationDraggable: (_) => widget.canStartDrag?.call(id) ?? true,
          dragItemsProvider: (_) => _statesForDrag(id),
          child: child,
        ),
      );
    });
  }
}
