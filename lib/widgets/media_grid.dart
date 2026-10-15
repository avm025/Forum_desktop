import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/media_dims.dart';
import '../utils/media_message_layout.dart';
import 'draggable_attachment_group.dart';
import 'media_thumb_tile.dart';

/// Медиа в сообщении: ряды без пустот, границы между файлами.
///
/// Короткий ЛКМ — открыть; сдвиг — DnD без открытия (одиночные сразу).
/// Группа: короткий ЛКМ — открыть; long-press — выделить; рамка — группа;
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
  /// Long-press / сдвиг — DnD без открытия.
  bool _dragArmed = false;
  bool _suppressOpen = false;
  int? _downHitIndex;
  Timer? _longPressTimer;

  static const _longPressDuration = Duration(milliseconds: 350);
  static const _dragSlop = 10.0;

  @override
  void initState() {
    super.initState();
    AttachmentSelection.ensureKeyboardBound();
    AttachmentSelection.clearToken.addListener(_onGlobalClear);
    AttachmentSelection.activeOwner.addListener(_onOwnerChanged);
    unawaited(_probeDimensions());
  }

  @override
  void didUpdateWidget(covariant MediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.files, widget.files) ||
        oldWidget.files.length != widget.files.length) {
      unawaited(_probeDimensions());
    }
  }

  /// Добиваем width/height — иначе пузырь квадратный / не по кадру.
  Future<void> _probeDimensions() async {
    var changed = false;
    for (final f in _list) {
      if (await MediaDims.ensure(f)) changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
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
    widget.onSelectionChanged?.call(const []);
  }

  void _onOwnerChanged() {
    if (!mounted || _selected.isEmpty) return;
    if (identical(AttachmentSelection.activeOwner.value, _owner)) return;
    setState(() => _selected.clear());
    widget.onSelectionChanged?.call(const []);
  }

  void _clearLocal({bool notify = true}) {
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

  /// Группа: long-press добавляет к выделению; повторный — снимает.
  void _toggleSelection(String id) {
    final next = Set<String>.from(_selected);
    if (next.contains(id)) {
      next.remove(id);
      if (next.isEmpty) {
        _clearLocal();
      } else {
        _applySelection(next);
      }
      return;
    }
    next.add(id);
    _applySelection(next);
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
    _dragArmed = false;
    _suppressOpen = false;
    _downHitIndex = _hitIndex(local, layout);
    _longPressTimer?.cancel();
    final hit = _downHitIndex;
    if (hit != null) {
      _longPressTimer = Timer(_longPressDuration, () {
        if (!mounted || _marqueeOrigin == null) return;
        _dragArmed = true;
        _suppressOpen = true;
        AttachmentSelection.suppressNextBubbleTap();
        // Одиночные — без галки; группа — выделить под DnD.
        if (_list.length > 1) {
          _toggleSelection(_idAt(hit));
        }
      });
    }
  }

  void _onPointerMove(PointerMoveEvent e, MediaMessageLayout layout) {
    if (e.buttons != kPrimaryButton) return;
    if (_marqueeOrigin == null) return;

    final local = _toLocal(e.position);
    final distance = (local - _marqueeOrigin!).distance;

    if (_list.length <= 1) {
      // Одиночное медиа: сдвиг = DnD, не открытие (без выделения).
      if (!_suppressOpen && distance >= _dragSlop) {
        _longPressTimer?.cancel();
        _suppressOpen = true;
        _dragArmed = true;
      }
      return;
    }

    // Группа: протягивание — рамка выделения.
    if (!_marqueeActive && distance < _dragSlop) return;

    _longPressTimer?.cancel();
    _suppressOpen = true;
    _dragArmed = true;
    setState(() {
      _marqueeActive = true;
      _marqueeCurrent = local;
    });
    _selectIntersecting(layout);
  }

  void _onPointerUp(PointerUpEvent e, MediaMessageLayout layout) {
    _longPressTimer?.cancel();
    _longPressTimer = null;

    // ПКМ / другие кнопки — только меню, не открытие.
    if (_marqueeOrigin == null) {
      _marqueeCurrent = null;
      _marqueeActive = false;
      _dragArmed = false;
      _suppressOpen = false;
      _downHitIndex = null;
      return;
    }

    final local = _toLocal(e.position);
    final wasMarquee = _marqueeActive;
    final suppressOpen = _suppressOpen || _dragArmed;
    final origin = _marqueeOrigin;

    _marqueeOrigin = null;
    _marqueeCurrent = null;
    _marqueeActive = false;
    _dragArmed = false;
    _suppressOpen = false;
    _downHitIndex = null;

    if (wasMarquee) {
      AttachmentSelection.suppressNextBubbleTap();
      setState(() {});
      return;
    }

    if (suppressOpen) {
      // Long-press / DnD — не открываем.
      AttachmentSelection.suppressNextBubbleTap();
      return;
    }

    if (origin == null) return;
    final hit = _hitIndex(local, layout);
    if (hit == null) {
      _clearLocal();
      return;
    }

    AttachmentSelection.suppressNextBubbleTap();
    // Короткий ЛКМ — открыть (одиночные и группа); выделение — long-press.
    _clearLocal();
    widget.onFileTap?.call(_list[hit]);
  }

  void _onSecondaryTapUp(TapUpDetails details, MediaMessageLayout layout) {
    AttachmentSelection.retainPointer();
    AttachmentSelection.suppressNextBubbleTap();
    // ПКМ только открывает меню — выделение не меняем.
    widget.onContextMenu?.call(details.globalPosition);
  }

  void _onPointerCancel() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    setState(() {
      _marqueeActive = false;
      _marqueeOrigin = null;
      _marqueeCurrent = null;
      _dragArmed = false;
      _suppressOpen = false;
      _downHitIndex = null;
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
        // Во время рамки DnD не начинаем.
        if (_marqueeActive) return false;
        // Одиночные — сразу; группа — после long-press / сдвига / выделения.
        if (list.length <= 1) return true;
        if (!_dragArmed && !_selected.contains(id)) return false;
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
                              selected: list.length > 1 &&
                                  _selected.contains(_idAt(i)),
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

    // Всегда MediaThumbTile: не переключать Image.memory ↔ Tile при появлении bytes
    // (это давало мигание превью при upload).
    if (hasBytes ||
        hasUrl ||
        (file.URL != null && file.URL!.trim().isNotEmpty) ||
        MediaThumbCache.needsRemoteThumbnail(file)) {
      content = MediaThumbTile(
        key: ValueKey('thumb_${_stableMediaKey(file)}'),
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
      // Нет URL/байтов — нейтральный фон вместо градиента с иконкой.
      content = ColoredBox(
        color: context.palette.bg3,
        child: SizedBox(width: width, height: height),
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

  /// Локальный путь / fname важнее hash: иначе remount при появлении hash.
  static String _stableMediaKey(MediaFile file) {
    final local = file.URL?.trim() ?? '';
    if (local.isNotEmpty && !local.startsWith('http')) return 'p_$local';
    if (file.fname.isNotEmpty) {
      return 'f_${file.fdir}_${file.fname}_${file.size}';
    }
    if (file.hash.isNotEmpty) return 'h_${file.hash}';
    if (file.url.isNotEmpty) return 'u_${file.url}';
    return 'k_${file.kind}_${file.size}';
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
