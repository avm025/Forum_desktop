import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/media_message_layout.dart';
import 'draggable_attachment_group.dart';
import 'media_thumb_tile.dart';

/// Медиа в сообщении: ряды без пустот, границы между файлами.
///
/// Один файл: ЛКМ — открыть, ПКМ — меню.
/// Группа: ЛКМ — выделить/снять; протянуть — рамка; двойной ЛКМ — открыть;
/// ПКМ — меню.
class MediaGrid extends StatefulWidget {
  final List<MediaFile> files;
  final double maxWidth;
  final void Function(MediaFile file)? onFileTap;
  /// Выделенные файлы после изменения (пусто → меню закрыть).
  final void Function(List<MediaFile> selected)? onSelectionChanged;
  /// ПКМ: показать контекстное меню.
  final void Function(Offset globalPosition)? onContextMenu;
  /// Без градиента/иконки, пока превью ещё нет (стартовая отрисовка чата).
  final bool deferPreview;

  const MediaGrid({
    super.key,
    required this.files,
    this.maxWidth = 280,
    this.onFileTap,
    this.onSelectionChanged,
    this.onContextMenu,
    this.deferPreview = false,
  });

  static const maxLayoutWidth = 980.0;
  static const _gap = 2.0;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  final Set<String> _selected = {};
  final GlobalKey _stackKey = GlobalKey();
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

  void _clearLocal({bool notify = true}) {
    _cancelPendingDeselect();
    if (_selected.isEmpty) return;
    setState(() => _selected.clear());
    if (identical(AttachmentSelection.activeOwner.value, _owner)) {
      AttachmentSelection.activeOwner.value = null;
    }
    if (notify) widget.onSelectionChanged?.call(const []);
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

  void _selectIntersecting(MediaMessageLayout layout) {
    final rect = _marqueeRect;
    if (rect == null) return;
    final next = <String>{};
    for (var i = 0; i < layout.tiles.length; i++) {
      final t = layout.tiles[i];
      final tileRect = Rect.fromLTWH(t.left, t.top, t.width, t.height);
      if (tileRect.overlaps(rect)) {
        next.add(_idAt(i));
      }
    }
    _applySelection(next);
  }

  int? _hitIndex(Offset local, MediaMessageLayout layout) {
    for (var i = 0; i < layout.tiles.length; i++) {
      final t = layout.tiles[i];
      if (Rect.fromLTWH(t.left, t.top, t.width, t.height).contains(local)) {
        return i;
      }
    }
    return null;
  }

  Offset _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.globalToLocal(global);
  }

  void _onPointerDown(PointerDownEvent e, MediaMessageLayout layout) {
    if (e.buttons != kPrimaryButton) return;
    AttachmentSelection.retainPointer();
    AttachmentSelection.claim(_owner);
    final local = _toLocal(e.position);
    _marqueeOrigin = local;
    _marqueeCurrent = local;
    _marqueeActive = false;
  }

  void _onPointerMove(PointerMoveEvent e, MediaMessageLayout layout) {
    if (e.buttons != kPrimaryButton) return;
    if (_marqueeOrigin == null) return;
    if (_list.length <= 1) return;

    final local = _toLocal(e.position);
    // Порог больше микродвижения клика, чтобы ЛКМ не превращался в рамку.
    if (!_marqueeActive && (local - _marqueeOrigin!).distance < 10) return;

    setState(() {
      _marqueeActive = true;
      _marqueeCurrent = local;
    });
    _cancelPendingDeselect();
    _selectIntersecting(layout);
  }

  void _onPointerUp(PointerUpEvent e, MediaMessageLayout layout) {
    final local = _toLocal(e.position);
    final wasMarquee = _marqueeActive;
    final origin = _marqueeOrigin;

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

    if (origin == null) return;
    final hit = _hitIndex(local, layout);
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

    // Одно медиа — ЛКМ сразу открывает.
    if (!isGroup) {
      widget.onFileTap?.call(_list[hit]);
      return;
    }

    // Группа: двойной ЛКМ — открыть, выделение визуально не трогаем.
    if (doubleTap) {
      _cancelPendingDeselect();
      widget.onFileTap?.call(_list[hit]);
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

  void _onSecondaryTapUp(TapUpDetails details, MediaMessageLayout layout) {
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

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox.shrink();

    final p = context.palette;
    final effectiveWidth = math
        .min(widget.maxWidth, MediaGrid.maxLayoutWidth)
        .clamp(120.0, MediaGrid.maxLayoutWidth);
    final list = _list;
    final layout = MediaMessageLayout.justified(
      files: list,
      width: effectiveWidth,
      gap: MediaGrid._gap,
    );

    return DraggableAttachmentGroup(
      files: list,
      selectedIds: Set<String>.from(_selected),
      canStartDrag: (id) {
        // Во время рамки DnD не начинаем; с невыделенного — рамка, не drag.
        if (_marqueeActive) return false;
        if (list.length <= 1) return true;
        return _selected.contains(id);
      },
      builder: (context, wrapFile) {
        return GestureDetector(
          onSecondaryTapUp: (d) => _onSecondaryTapUp(d, layout),
          child: Listener(
            onPointerDown: (e) => _onPointerDown(e, layout),
            onPointerMove: (e) => _onPointerMove(e, layout),
            onPointerUp: (e) => _onPointerUp(e, layout),
            onPointerCancel: (_) => _onPointerCancel(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: list.length > 1 ? p.border1 : Colors.transparent,
                child: SizedBox(
                  key: _stackKey,
                  width: layout.totalWidth,
                  height: layout.totalHeight,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (var i = 0; i < list.length; i++)
                        Positioned(
                          left: layout.tiles[i].left,
                          top: layout.tiles[i].top,
                          width: layout.tiles[i].width,
                          height: layout.tiles[i].height,
                          child: wrapFile(
                            list[i],
                            _tile(
                              list[i],
                              width: layout.tiles[i].width,
                              height: layout.tiles[i].height,
                              playIconSize: layout.tiles[i].playIconSize,
                              selected: _selected.contains(_idAt(i)),
                            ),
                          ),
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
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(
    MediaFile file, {
    required double width,
    required double height,
    required double playIconSize,
    required bool selected,
  }) {
    final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
    final hasUrl = file.url.isNotEmpty;

    Widget content;

    if (hasBytes && file.bytes!.length < 2 * 1024 * 1024) {
      content = Image.memory(
        file.bytes!,
        key: ValueKey('mem_${file.hash}'),
        fit: BoxFit.cover,
        width: width,
        height: height,
        gaplessPlayback: true,
        cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        cacheHeight: (height * MediaQuery.devicePixelRatioOf(context)).round(),
      );
    } else if (hasUrl ||
        (file.URL != null && file.URL!.trim().isNotEmpty) ||
        MediaThumbCache.needsRemoteThumbnail(file)) {
      content = MediaThumbTile(
        // Ключ без размера: иначе при ресайзе окна State сбрасывается
        // и на мгновение показывается placeholder.
        key: ValueKey(
          'thumb_${file.hash.isNotEmpty ? file.hash : (file.URL ?? file.url)}',
        ),
        file: file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        blankWhileLoading: widget.deferPreview,
      );
    } else if (widget.deferPreview) {
      content = ColoredBox(
        color: context.palette.bg2,
        child: SizedBox(width: width, height: height),
      );
    } else {
      final gradient = AppColors.avatarGradientFor(
        file.hash.isNotEmpty ? file.hash : '${file.width}x${file.height}',
      );
      content = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Colors.white54, size: 40),
      );
    }

    content = SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (!widget.deferPreview)
            _overlay(file, playIconSize: playIconSize),
          if (selected) ...[
            const ColoredBox(color: Color(0x332E7CF6)),
            const Positioned(
              top: 6,
              right: 6,
              child: _TelegramCheckBadge(),
            ),
          ],
        ],
      ),
    );

    return content;
  }

  Widget _overlay(
    MediaFile file, {
    required double playIconSize,
  }) {
    if (!file.isVideo) return const SizedBox.shrink();

    return Stack(
      children: [
        Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Colors.white.withValues(alpha: 0.92),
            size: playIconSize,
          ),
        ),
        if (file.duration > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatDuration(file.duration),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Кружок с галкой — как выделение медиа в Telegram.
class _TelegramCheckBadge extends StatelessWidget {
  const _TelegramCheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2E7CF6),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 14,
        color: Colors.white,
      ),
    );
  }
}
