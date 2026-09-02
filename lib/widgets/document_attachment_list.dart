import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../utils/attachment_selection.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_message_layout.dart';
import 'draggable_attachment_group.dart';
import 'file_row_tile.dart';

/// Список документов в пузыре.
///
/// Один файл: ЛКМ — открыть (если загружен), ПКМ — меню.
/// Группа: ЛКМ — выделить/снять, двойной ЛКМ — открыть, ПКМ — меню.
class DocumentAttachmentList extends StatefulWidget {
  final List<MediaFile> files;
  final bool onAccent;
  final double maxWidth;
  final void Function(MediaFile file) onOpen;
  final void Function(List<MediaFile> selected)? onSelectionChanged;
  final void Function(Offset globalPosition)? onContextMenu;
  final Widget? footer;

  const DocumentAttachmentList({
    super.key,
    required this.files,
    required this.onAccent,
    required this.maxWidth,
    required this.onOpen,
    this.onSelectionChanged,
    this.onContextMenu,
    this.footer,
  });

  static const _rowGap = 8.0;
  static const _approxRowHeight = 64.0;

  @override
  State<DocumentAttachmentList> createState() => _DocumentAttachmentListState();
}

class _DocumentAttachmentListState extends State<DocumentAttachmentList> {
  final Set<String> _selected = {};
  final GlobalKey _listKey = GlobalKey();
  final Map<int, GlobalKey> _rowKeys = {};
  final Object _owner = Object();

  Offset? _marqueeOrigin;
  Offset? _marqueeCurrent;
  bool _marqueeActive = false;
  int? _tapIndex;
  DateTime? _lastTapAt;
  Timer? _deselectTimer;
  String? _pendingDeselectId;

  static const _doubleTapWindow = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    AttachmentSelection.ensureKeyboardBound();
    AttachmentSelection.clearToken.addListener(_onGlobalClear);
    AttachmentSelection.activeOwner.addListener(_onOwnerChanged);
  }

  @override
  void dispose() {
    _deselectTimer?.cancel();
    AttachmentSelection.clearToken.removeListener(_onGlobalClear);
    AttachmentSelection.activeOwner.removeListener(_onOwnerChanged);
    if (identical(AttachmentSelection.activeOwner.value, _owner)) {
      AttachmentSelection.activeOwner.value = null;
    }
    super.dispose();
  }

  void _cancelPendingDeselect() {
    _deselectTimer?.cancel();
    _deselectTimer = null;
    _pendingDeselectId = null;
  }

  void _scheduleDeselect(String id) {
    _cancelPendingDeselect();
    _pendingDeselectId = id;
    _deselectTimer = Timer(_doubleTapWindow, () {
      if (!mounted || _pendingDeselectId != id) return;
      _pendingDeselectId = null;
      _deselectTimer = null;
      final next = Set<String>.from(_selected)..remove(id);
      if (next.isEmpty) {
        _clearLocal();
      } else {
        _applySelection(next);
      }
    });
  }

  void _onGlobalClear() {
    if (!mounted || _selected.isEmpty) return;
    setState(() => _selected.clear());
    widget.onSelectionChanged?.call(const []);
  }

  void _onOwnerChanged() {
    if (!mounted || _selected.isEmpty) return;
    if (identical(AttachmentSelection.activeOwner.value, _owner)) return;
    setState(() => _selected.clear());
    widget.onSelectionChanged?.call(const []);
  }

  void _clearLocal() {
    _cancelPendingDeselect();
    if (_selected.isEmpty) return;
    setState(() => _selected.clear());
    if (identical(AttachmentSelection.activeOwner.value, _owner)) {
      AttachmentSelection.activeOwner.value = null;
    }
    widget.onSelectionChanged?.call(const []);
  }

  void _applySelection(Set<String> next) {
    AttachmentSelection.claim(_owner);
    setState(() {
      _selected
        ..clear()
        ..addAll(next);
    });
    widget.onSelectionChanged?.call(_selectedFiles());
  }

  List<MediaFile> _selectedFiles() {
    final out = <MediaFile>[];
    for (var i = 0; i < _list.length; i++) {
      if (_selected.contains(_idAt(i))) out.add(_list[i]);
    }
    return out;
  }

  List<MediaFile> get _list =>
      widget.files.take(MediaMessageLayout.maxFiles).toList();

  String _idAt(int index) =>
      DraggableAttachmentGroup.fileId(_list[index], index);

  Rect? get _marqueeRect {
    final a = _marqueeOrigin;
    final b = _marqueeCurrent;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

  Offset _toLocal(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.globalToLocal(global);
  }

  Rect? _rowRect(int index) {
    final key = _rowKeys[index];
    final rowBox = key?.currentContext?.findRenderObject() as RenderBox?;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null || listBox == null || !rowBox.hasSize) return null;
    final topLeft = listBox.globalToLocal(rowBox.localToGlobal(Offset.zero));
    return topLeft & rowBox.size;
  }

  int? _hitIndex(Offset local) {
    for (var i = 0; i < _list.length; i++) {
      final rect = _rowRect(i);
      if (rect != null && rect.contains(local)) return i;
    }
    // Fallback по приблизительной высоте, пока ключи не измеряны.
    if (_list.isEmpty) return null;
    var y = 0.0;
    for (var i = 0; i < _list.length; i++) {
      const h = DocumentAttachmentList._approxRowHeight;
      if (local.dy >= y && local.dy <= y + h) return i;
      y += h + DocumentAttachmentList._rowGap;
    }
    return null;
  }

  void _selectIntersecting() {
    final rect = _marqueeRect;
    if (rect == null) return;
    final next = <String>{};
    for (var i = 0; i < _list.length; i++) {
      final row = _rowRect(i);
      if (row != null && row.overlaps(rect)) {
        next.add(_idAt(i));
      }
    }
    _applySelection(next);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    AttachmentSelection.retainPointer();
    AttachmentSelection.claim(_owner);
    final local = _toLocal(e.position);
    _marqueeOrigin = local;
    _marqueeCurrent = local;
    _marqueeActive = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.buttons != kPrimaryButton) return;
    if (_marqueeOrigin == null) return;
    if (_list.length <= 1) return;

    final local = _toLocal(e.position);
    if (!_marqueeActive && (local - _marqueeOrigin!).distance < 10) return;

    setState(() {
      _marqueeActive = true;
      _marqueeCurrent = local;
    });
    _cancelPendingDeselect();
    _selectIntersecting();
  }

  void _onPointerUp(PointerUpEvent e) {
    final local = _toLocal(e.position);
    final wasMarquee = _marqueeActive;

    if (wasMarquee) {
      AttachmentSelection.suppressNextBubbleTap();
      setState(() {
        _marqueeActive = false;
        _marqueeOrigin = null;
        _marqueeCurrent = null;
      });
      return;
    }

    _marqueeOrigin = null;
    _marqueeCurrent = null;
    _marqueeActive = false;

    final hit = _hitIndex(local);
    if (hit == null) {
      _clearLocal();
      return;
    }

    final id = _idAt(hit);
    final isGroup = _list.length > 1;
    final now = DateTime.now();
    final doubleTap = _tapIndex == hit &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < _doubleTapWindow;

    _tapIndex = hit;
    _lastTapAt = now;

    AttachmentSelection.suppressNextBubbleTap();

    // Один файл — ЛКМ открывает.
    if (!isGroup) {
      unawaited(_openIfDownloaded(_list[hit]));
      return;
    }

    // Группа: двойной ЛКМ — открыть, выделение визуально не трогаем.
    if (doubleTap) {
      _cancelPendingDeselect();
      unawaited(_openIfDownloaded(_list[hit]));
      return;
    }

    // Группа: ЛКМ — выделить сразу; снять — с задержкой (ждём возможный dblclick).
    if (_selected.contains(id)) {
      _scheduleDeselect(id);
      return;
    }
    _cancelPendingDeselect();
    _applySelection({..._selected, id});
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    AttachmentSelection.retainPointer();
    AttachmentSelection.suppressNextBubbleTap();
    // ПКМ только открывает меню — выделение не меняем.
    widget.onContextMenu?.call(details.globalPosition);
  }

  void _onPointerCancel() {
    setState(() {
      _marqueeActive = false;
      _marqueeOrigin = null;
      _marqueeCurrent = null;
    });
  }

  /// Как в Telegram Desktop: открывать только после явной загрузки.
  Future<void> _openIfDownloaded(MediaFile file) async {
    if (!await MediaFileLoader.isDownloaded(file)) return;
    if (!mounted) return;
    widget.onOpen(file);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list.isEmpty) return const SizedBox.shrink();

    for (var i = 0; i < list.length; i++) {
      _rowKeys.putIfAbsent(i, GlobalKey.new);
    }

    return DraggableAttachmentGroup(
      files: list,
      selectedIds: Set<String>.from(_selected),
      nameOnlyDragPreview: true,
      canStartDrag: (id) {
        if (_marqueeActive) return false;
        if (list.length <= 1) {
          for (var i = 0; i < list.length; i++) {
            if (_idAt(i) != id) continue;
            return MediaFileLoader.hasLocalCopySync(list[i]);
          }
          return false;
        }
        if (!_selected.contains(id)) return false;
        for (var i = 0; i < list.length; i++) {
          if (_idAt(i) != id) continue;
          return MediaFileLoader.hasLocalCopySync(list[i]);
        }
        return false;
      },
      builder: (context, wrapFile) {
        return GestureDetector(
          onSecondaryTapUp: _onSecondaryTapUp,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) => _onPointerCancel(),
            child: Stack(
              key: _listKey,
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0)
                        const SizedBox(height: DocumentAttachmentList._rowGap),
                      KeyedSubtree(
                        key: _rowKeys[i],
                        child: wrapFile(
                          list[i],
                          FileRowTile(
                            file: list[i],
                            onAccent: widget.onAccent,
                            maxWidth: widget.maxWidth,
                            selected: _selected.contains(_idAt(i)),
                            onTap: () {
                              // Клик обрабатывает Listener (выделение / открытие).
                            },
                          ),
                        ),
                      ),
                    ],
                    if (widget.footer != null)
                      Padding(
                        padding: EdgeInsets.only(top: list.isNotEmpty ? 6 : 0),
                        child: widget.footer!,
                      ),
                  ],
                ),
                if (_marqueeActive && _marqueeRect != null)
                  Positioned.fromRect(
                    rect: _marqueeRect!,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x332E7CF6),
                          border: Border.all(
                            color: const Color(0xFF2E7CF6),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
