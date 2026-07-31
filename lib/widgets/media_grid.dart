import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/media_message_layout.dart';
import 'draggable_attachment_group.dart';
import 'media_thumb_tile.dart';

/// Медиа в сообщении: ряды без пустот, границы между файлами,
/// DnD файла сразу (без предвыбора), рамка выделения — Shift+жест,
/// групповой DnD — после выделения.
class MediaGrid extends StatefulWidget {
  final List<MediaFile> files;
  final double maxWidth;
  final void Function(MediaFile file)? onFileTap;

  const MediaGrid({
    super.key,
    required this.files,
    this.maxWidth = 280,
    this.onFileTap,
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

  @override
  void initState() {
    super.initState();
    AttachmentSelection.ensureKeyboardBound();
    AttachmentSelection.clearToken.addListener(_onGlobalClear);
    AttachmentSelection.activeOwner.addListener(_onOwnerChanged);
  }

  @override
  void dispose() {
    AttachmentSelection.clearToken.removeListener(_onGlobalClear);
    AttachmentSelection.activeOwner.removeListener(_onOwnerChanged);
    if (identical(AttachmentSelection.activeOwner.value, _owner)) {
      AttachmentSelection.activeOwner.value = null;
    }
    super.dispose();
  }

  void _onGlobalClear() {
    if (!mounted || _selected.isEmpty) return;
    setState(() => _selected.clear());
  }

  void _onOwnerChanged() {
    if (!mounted || _selected.isEmpty) return;
    if (identical(AttachmentSelection.activeOwner.value, _owner)) return;
    setState(() => _selected.clear());
  }

  void _clearLocal() {
    if (_selected.isEmpty) return;
    setState(() => _selected.clear());
    if (identical(AttachmentSelection.activeOwner.value, _owner)) {
      AttachmentSelection.activeOwner.value = null;
    }
  }

  void _applySelection(Set<String> next) {
    AttachmentSelection.claim(_owner);
    setState(() {
      _selected
        ..clear()
        ..addAll(next);
    });
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
    final hit = _hitIndex(local, layout);
    _marqueeOrigin = local;
    _marqueeCurrent = local;
    _marqueeActive = false;

    final hitId = hit == null ? null : _idAt(hit);
    // Старт на невыделенном — готовим рамку; на выделенном — DnD группы/файла.
    if (hitId == null || !_selected.contains(hitId)) {
      _marqueeActive = false; // активируется при движении
    }
  }

  void _onPointerMove(PointerMoveEvent e, MediaMessageLayout layout) {
    if (e.buttons != kPrimaryButton) return;
    if (_marqueeOrigin == null) return;

    // Рамка выделения — только с Shift; иначе жест отдаём под DnD файла.
    final wantMarquee = HardwareKeyboard.instance.isShiftPressed || _marqueeActive;
    if (!wantMarquee) return;

    final local = _toLocal(e.position);
    if ((local - _marqueeOrigin!).distance < 4) return;

    setState(() {
      _marqueeActive = true;
      _marqueeCurrent = local;
    });
    _selectIntersecting(layout);
  }

  void _onPointerUp(PointerUpEvent e, MediaMessageLayout layout) {
    final local = _toLocal(e.position);
    final wasMarquee = _marqueeActive;
    final origin = _marqueeOrigin;

    if (wasMarquee) {
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
    final now = DateTime.now();
    final doubleTap = _tapIndex == hit &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < const Duration(milliseconds: 350);

    _tapIndex = hit;
    _lastTapAt = now;

    if (doubleTap) {
      widget.onFileTap?.call(_list[hit]);
      return;
    }

    // Клик переключает файл в мультивыборе (без модификаторов).
    final next = Set<String>.from(_selected);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    if (next.isEmpty) {
      _clearLocal();
    } else {
      _applySelection(next);
    }
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
      // DnD сразу без предвыбора; рамка — Shift+жест.
      canStartDrag: (id) =>
          !_marqueeActive && !HardwareKeyboard.instance.isShiftPressed,
      builder: (context, wrapFile) {
        return Listener(
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

    if (hasBytes) {
      content = Image.memory(
        file.bytes!,
        key: ValueKey('${file.hash}_${width.round()}x${height.round()}'),
        fit: BoxFit.cover,
        width: width,
        height: height,
      );
    } else if (hasUrl || MediaThumbCache.needsRemoteThumbnail(file)) {
      content = MediaThumbTile(
        key: ValueKey('${file.hash}_${width.round()}x${height.round()}'),
        file: file,
        width: width,
        height: height,
        fit: BoxFit.cover,
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
          _overlay(file, playIconSize: playIconSize),
          if (selected)
            const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x332E7CF6),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFF2E7CF6), width: 2),
                ),
              ),
            ),
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
