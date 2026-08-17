import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/chat_file_dnd.dart';
import '../utils/cursor_position.dart';
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
  final Set<String> selectedIds;
  final bool Function(String fileId)? canStartDrag;
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

class _DraggableAttachmentGroupState extends State<DraggableAttachmentGroup>
    with TickerProviderStateMixin {
  final Map<String, GlobalKey<DragItemWidgetState>> _keys = {};
  /// Ключи на визуальный тайл (для размера исходной картинки).
  final Map<String, GlobalKey> _tileKeys = {};

  OverlayEntry? _dragOverlay;
  _DragVisualState? _visual;
  PointerRoute? _pointerRoute;
  Timer? _cursorTimer;
  bool _cursorOriginSynced = false;
  bool _returningHome = false;
  AnimationController? _returnController;
  int _cursorPollGen = 0;
  /// Overlay box для перевода global → local Positioned.
  RenderBox? _overlayBox;
  /// Сессия, для которой уже показан Overlay (не создавать повторно на каждый item).
  DragSession? _overlaySession;

  static const double _mediaPreviewSize = 112;
  /// Как в Telegram Web — средний фиксированный плюс.
  static const double _plusSize = 30;
  static const double _plusIconSize = 18;
  static const Color _telegramPlusGreen = Color(0xFF31B545);

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

  /// Файлы для превью: выделенная группа или один файл.
  List<MediaFile> _filesForDrag(String startedId, MediaFile startedFile) {
    final selected = widget.selectedIds;
    if (!selected.contains(startedId) || selected.length <= 1) {
      return [startedFile];
    }
    final out = <MediaFile>[];
    // Начатый файл — спереди стопки.
    if (ChatFileDnd.isMediaAttachment(startedFile)) {
      out.add(startedFile);
    }
    for (var i = 0; i < widget.files.length; i++) {
      final f = widget.files[i];
      final id = DraggableAttachmentGroup.fileId(f, i);
      if (id == startedId) continue;
      if (!selected.contains(id)) continue;
      if (!ChatFileDnd.isMediaAttachment(f)) continue;
      out.add(f);
    }
    return out.isEmpty ? [startedFile] : out;
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

  Widget _mediaImage(
    MediaFile file, {
    required double width,
    required double height,
  }) {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return Image.memory(
        file.bytes!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    final thumb = MediaThumbCache.peekSync(file);
    if (thumb != null) {
      return Image.file(
        thumb,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _fallback(file, width, height),
      );
    }

    final local = file.URL?.trim();
    if (local != null && local.isNotEmpty) {
      try {
        final path = local.startsWith('file://')
            ? Uri.parse(local).toFilePath()
            : local;
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 0) {
          return Image.file(
            f,
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(file, width, height),
          );
        }
      } catch (_) {}
    }

    return _fallback(file, width, height);
  }

  Widget _fallback(MediaFile file, double width, double height) {
    final gradient = AppColors.avatarGradientFor(
      file.hash.isNotEmpty ? file.hash : file.url,
    );
    return Container(
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
      child: Icon(
        file.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        color: Colors.white54,
        size: math.min(40, width * 0.35),
      ),
    );
  }

  /// Всегда «+», даже при групповом перетаскивании.
  Widget _plusBadge() {
    return SizedBox(
      width: _plusSize,
      height: _plusSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _telegramPlusGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.add_rounded,
            color: Colors.white,
            size: _plusIconSize,
          ),
        ),
      ),
    );
  }

  /// Стопка превью (до 3 картинок) + плюс по центру.
  Widget _stackedMediaPreview({
    required List<MediaFile> files,
    required double width,
    required double height,
    required double radius,
  }) {
    final stack = files.take(3).toList(growable: false);
    // Запас под смещение стопки, чтобы Positioned не обрезал задние карточки.
    final pad = stack.length > 1 ? (stack.length - 1) * 7.0 : 0.0;
    return SizedBox(
      width: width + pad,
      height: height + pad,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = stack.length - 1; i >= 0; i--)
            Transform.translate(
              offset: Offset(i * 7.0, i * 7.0),
              child: Transform.rotate(
                angle: i * 0.04,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: _mediaImage(
                      stack[i],
                      width: width,
                      height: height,
                    ),
                  ),
                ),
              ),
            ),
          _plusBadge(),
        ],
      ),
    );
  }

  /// Пустой native ghost: визуал только Overlay, иначе macOS рисует
  /// второй (и N-й для группы) снимок рядом с копией.
  Widget _invisibleNativeGhost() {
    return SnapshotSettings(
      constraintsTransform: (_) =>
          const BoxConstraints.tightFor(width: 1, height: 1),
      child: const SizedBox(width: 1, height: 1),
    );
  }

  void _stopPointerRoute() {
    final route = _pointerRoute;
    if (route != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
      _pointerRoute = null;
    }
  }

  void _stopCursorTimer() {
    _cursorTimer?.cancel();
    _cursorTimer = null;
  }

  void _disposeDragOverlay() {
    _stopPointerRoute();
    _stopCursorTimer();
    _returnController?.dispose();
    _returnController = null;
    _returningHome = false;
    _dragOverlay?.remove();
    _dragOverlay = null;
    _visual = null;
    _overlayBox = null;
    _cursorOriginSynced = false;
    _overlaySession = null;
    _cursorPollGen++;
  }

  /// [global] — координаты Flutter global; Positioned считает от Overlay.
  void _updatePointer(Offset global, {bool fromNativeCursor = false}) {
    if (_returningHome) return;
    final v = _visual;
    final entry = _dragOverlay;
    if (v == null || entry == null) return;

    if (fromNativeCursor && !_cursorOriginSynced) {
      _cursorOriginSynced = true;
    }

    var pointer = global;
    final box = _overlayBox;
    if (box != null && box.attached) {
      pointer = box.globalToLocal(global);
    }

    if ((pointer - v.pointer).distance < 0.5) return;
    _visual = v.copyWith(pointer: pointer);
    entry.markNeedsBuild();
  }

  /// Уменьшение только после смещения на половину размера исходной картинки.
  static double _shrinkT({
    required Offset center,
    required Offset originCenter,
    required Size originSize,
  }) {
    final half = 0.5 * math.max(originSize.width, originSize.height);
    if (half <= 0) return 0;
    final distance = (center - originCenter).distance;
    if (distance < half) return 0;
    // Дальше плавно к мини-размеру на ещё одну «половину».
    return Curves.easeOutCubic.transform(
      ((distance - half) / half).clamp(0.0, 1.0),
    );
  }

  /// Видимый возврат к центру оригинала, затем исчезновение.
  /// Стартует сразу при отпускании (без ожидания dragCompleted).
  void _animateReturnHome() {
    if (_returningHome) return;
    final v = _visual;
    final entry = _dragOverlay;
    if (v == null || entry == null) {
      _disposeDragOverlay();
      return;
    }

    _returningHome = true;
    // Сразу отвязываем курсор — иначе копия «стоит», пока идут события.
    _stopPointerRoute();
    _stopCursorTimer();

    final fromPointer = v.pointer;
    final toPointer = v.originCenter;
    final fromT = _shrinkT(
      center: fromPointer,
      originCenter: v.originCenter,
      originSize: v.originSize,
    );

    _returnController?.dispose();
    _returnController = null;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _returnController = controller;

    void apply(double t) {
      if (!mounted || _visual == null || _dragOverlay == null) return;
      // 0…0.82 — полёт к центру; 0.82…1 — исчезновение на месте.
      final moveT = Curves.easeInOutCubic.transform((t / 0.82).clamp(0.0, 1.0));
      final fade = t < 0.82
          ? 1.0
          : (1.0 - (t - 0.82) / 0.18).clamp(0.0, 1.0);
      final ptr = Offset.lerp(fromPointer, toPointer, moveT)!;
      final shrink = ui.lerpDouble(fromT, 0, moveT)!;
      _visual = v.copyWith(
        pointer: ptr,
        returnShrinkT: shrink,
        opacity: fade,
      );
      entry.markNeedsBuild();
    }

    controller.addListener(() => apply(controller.value));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _disposeDragOverlay();
      }
    });
    apply(0);
    controller.forward();
  }

  void _onDragSessionEnded(DragSession session) {
    final op = session.dragCompleted.value;
    final copied = op == DropOperation.copy ||
        op == DropOperation.move ||
        op == DropOperation.link;
    AttachmentSelection.clear();
    if (copied) {
      // Успешный drop — убираем копию даже если уже шёл возврат.
      _disposeDragOverlay();
      return;
    }
    if (_returningHome) return;
    _animateReturnHome();
  }

  /// Старт: копия ровно поверх исходного тайла (центры совпадают).
  void _startDistanceDragOverlay({
    required List<MediaFile> files,
    required OverlayState overlay,
    required Offset originTopLeft,
    required Size originSize,
    required int count,
    required DragSession session,
  }) {
    // Один Overlay на сессию — иначе каждый DragItem создаёт ещё одну копию.
    if (_overlaySession == session && _dragOverlay != null) {
      return;
    }
    _disposeDragOverlay();
    _overlaySession = session;

    final overlayCtx = overlay.context;
    final overlayBox = overlayCtx.findRenderObject() as RenderBox?;
    _overlayBox = overlayBox;

    final safeSize = Size(
      math.max(originSize.width, 48),
      math.max(originSize.height, 48),
    );

    final originTopLeftLocal = (overlayBox != null && overlayBox.attached)
        ? overlayBox.globalToLocal(originTopLeft)
        : originTopLeft;
    final originRect = originTopLeftLocal & safeSize;
    final originCenter = originRect.center;

    _visual = _DragVisualState(
      files: files,
      count: count,
      originCenter: originCenter,
      originSize: safeSize,
      originRect: originRect,
      pointer: originCenter,
    );

    _dragOverlay = OverlayEntry(
      builder: (ctx) {
        final v = _visual;
        if (v == null) return const SizedBox.shrink();

        final center = v.pointer;
        final t = v.returnShrinkT ??
            _shrinkT(
              center: center,
              originCenter: v.originCenter,
              originSize: v.originSize,
            );

        final w = ui.lerpDouble(v.originSize.width, _mediaPreviewSize, t)!;
        final h = ui.lerpDouble(v.originSize.height, _mediaPreviewSize, t)!;
        final radius = ui.lerpDouble(4, 12, t)!;
        final stackPad = v.files.length > 1
            ? (math.min(v.files.length, 3) - 1) * 7.0
            : 0.0;
        final left = center.dx - (w + stackPad) / 2;
        final top = center.dy - (h + stackPad) / 2;

        // Единственная видимая копия — Overlay (native ghost пустой).
        final overlayOpacity = v.opacity;

        return Stack(
          children: [
            Positioned.fill(
              child: DropMonitor(
                formats: const [Formats.fileUri],
                hitTestBehavior: HitTestBehavior.translucent,
                onDropOver: (event) {
                  _updatePointer(event.position.global);
                },
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: IgnorePointer(
                child: Opacity(
                  opacity: overlayOpacity,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _stackedMediaPreview(
                      files: v.files,
                      width: w,
                      height: h,
                      radius: radius,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_dragOverlay!);

    void onPointer(PointerEvent e) {
      if (_returningHome) return;
      // Только движение: PointerUp/Cancel приходят и при старте native drag
      // (OS забирает жест) — по ним нельзя стартовать возврат.
      if (e is PointerMoveEvent || e is PointerHoverEvent) {
        _updatePointer(e.position);
      }
    }

    _pointerRoute = onPointer;
    GestureBinding.instance.pointerRouter.addGlobalRoute(onPointer);

    if (CursorPosition.isSupported) {
      final gen = ++_cursorPollGen;
      var sawButtonDown = false;
      _cursorTimer = Timer.periodic(const Duration(milliseconds: 16), (_) async {
        if (gen != _cursorPollGen || _returningHome) return;
        final snap = await CursorPosition.getSnapshot();
        if (gen != _cursorPollGen || _returningHome) return;
        if (snap == null) return;

        _updatePointer(snap.position, fromNativeCursor: true);

        // Отпускание ЛКМ — мгновенный старт возврата.
        // session.dragging / dragCompleted от native DnD приходят с лагом.
        if (snap.primaryDown) {
          sawButtonDown = true;
          return;
        }
        if (!sawButtonDown) return;

        final op = session.dragCompleted.value;
        final copied = op == DropOperation.copy ||
            op == DropOperation.move ||
            op == DropOperation.link;
        if (copied) {
          AttachmentSelection.clear();
          _disposeDragOverlay();
        } else {
          AttachmentSelection.clear();
          _animateReturnHome();
        }
      });
    }

    void onDraggingChanged() {
      if (session.dragging.value) return;
      session.dragging.removeListener(onDraggingChanged);
      // Отпускание кнопки: dragging=false — самый ранний надёжный сигнал.
      // Не ждём dragCompleted, иначе копия «висит» на месте.
      final op = session.dragCompleted.value;
      final copied = op == DropOperation.copy ||
          op == DropOperation.move ||
          op == DropOperation.link;
      if (copied) {
        AttachmentSelection.clear();
        _disposeDragOverlay();
      } else {
        AttachmentSelection.clear();
        _animateReturnHome();
      }
    }

    void onDragCompleted() {
      if (session.dragCompleted.value == null) return;
      session.dragCompleted.removeListener(onDragCompleted);
      _onDragSessionEnded(session);
    }

    session.dragging.addListener(onDraggingChanged);
    session.dragCompleted.addListener(onDragCompleted);
  }

  Future<void> _prepareMediaPreview(MediaFile file, BuildContext? ctx) async {
    try {
      File? thumb = MediaThumbCache.peekSync(file);
      thumb ??= await MediaThumbCache.getIfExists(file);
      thumb ??= await MediaThumbCache.ensureThumbnail(file);
      if (ctx != null && ctx.mounted) {
        await precacheImage(FileImage(thumb), ctx);
      }
    } catch (_) {
      if (file.bytes != null &&
          file.bytes!.isNotEmpty &&
          ctx != null &&
          ctx.mounted) {
        try {
          await precacheImage(MemoryImage(file.bytes!), ctx);
        } catch (_) {}
      }
    }
  }

  ({Offset topLeft, Size size})? _measureTile(String id) {
    final tileCtx = _tileKeys[id]?.currentContext;
    final box = tileCtx?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      return (topLeft: box.localToGlobal(Offset.zero), size: box.size);
    }
    final dragCtx = _keys[id]?.currentContext;
    final dragBox = dragCtx?.findRenderObject() as RenderBox?;
    if (dragBox != null && dragBox.hasSize && dragBox.attached) {
      return (
        topLeft: dragBox.localToGlobal(Offset.zero),
        size: dragBox.size,
      );
    }
    return null;
  }

  Widget? Function(BuildContext, Widget)? _previewBuilder(
    MediaFile file,
    String fileId,
  ) {
    if (widget.nameOnlyDragPreview) {
      return (context, _) => _namePreview(context, file);
    }
    if (ChatFileDnd.isMediaAttachment(file)) {
      // Пустой native ghost: единственная копия — Overlay.
      // Иначе OS рисует ещё один снимок (и по одному на каждый item группы).
      return (context, _) => _invisibleNativeGhost();
    }
    return null;
  }

  @override
  void dispose() {
    _disposeDragOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatFileDnd.isSupported || widget.files.isEmpty) {
      return widget.builder(context, (_, child) => child);
    }

    final nextKeys = <String, GlobalKey<DragItemWidgetState>>{};
    final nextTiles = <String, GlobalKey>{};
    for (var i = 0; i < widget.files.length; i++) {
      final id = DraggableAttachmentGroup.fileId(widget.files[i], i);
      nextKeys[id] = _keys[id] ?? GlobalKey<DragItemWidgetState>();
      nextTiles[id] = _tileKeys[id] ?? GlobalKey();
    }
    _keys
      ..clear()
      ..addAll(nextKeys);
    _tileKeys
      ..clear()
      ..addAll(nextTiles);

    return widget.builder(context, (file, child) {
      final index = widget.files.indexOf(file);
      final id = DraggableAttachmentGroup.fileId(file, index < 0 ? 0 : index);
      final key = _keys.putIfAbsent(id, GlobalKey<DragItemWidgetState>.new);
      final tileKey = _tileKeys.putIfAbsent(id, GlobalKey.new);
      final localId = 'forum-file-$id';
      final preview = _previewBuilder(file, id);

      return DragItemWidget(
        key: key,
        allowedOperations: () => [DropOperation.copy],
        canAddItemToExistingSession: true,
        liftBuilder: preview,
        dragBuilder: preview,
        dragItemProvider: (request) async {
          final measured = _measureTile(id);
          final overlayCtx = key.currentContext;
          final overlay = overlayCtx != null
              ? Overlay.maybeOf(overlayCtx, rootOverlay: true)
              : null;

          if (await request.session.hasLocalData(localId)) {
            return null;
          }

          if (ChatFileDnd.isMediaAttachment(file) &&
              !widget.nameOnlyDragPreview &&
              measured != null &&
              overlay != null) {
            final dragFiles = _filesForDrag(id, file);
            _startDistanceDragOverlay(
              files: dragFiles,
              overlay: overlay,
              originTopLeft: measured.topLeft,
              originSize: measured.size,
              count: dragFiles.length,
              session: request.session,
            );
            // Дождаться превью до native snapshot (после return provider).
            await Future.wait([
              for (final f in dragFiles)
                _prepareMediaPreview(f, key.currentContext),
            ]);
          }

          final item =
              await ChatFileDnd.buildDragItem(file, localId: localId);
          if (item == null) {
            _disposeDragOverlay();
            return null;
          }

          void onDraggingChanged() {
            if (!request.session.dragging.value) {
              request.session.dragging.removeListener(onDraggingChanged);
              // Завершение обрабатывает listener в _startDistanceDragOverlay.
              // Если Overlay не стартовал — просто очищаем выделение.
              if (_dragOverlay == null) {
                AttachmentSelection.clear();
              }
            }
          }

          request.session.dragging.addListener(onDraggingChanged);
          return item;
        },
        child: DraggableWidget(
          isLocationDraggable: (_) => widget.canStartDrag?.call(id) ?? true,
          dragItemsProvider: (_) => _statesForDrag(id),
          child: KeyedSubtree(
            key: tileKey,
            child: child,
          ),
        ),
      );
    });
  }
}

class _DragVisualState {
  final List<MediaFile> files;
  final int count;
  final Offset originCenter;
  final Size originSize;
  final Rect originRect;
  /// Центр копии (= позиция курсора во время drag).
  final Offset pointer;
  /// Во время возврата домой — принудительный shrink (иначе считаем по геометрии).
  final double? returnShrinkT;
  final double opacity;

  const _DragVisualState({
    required this.files,
    required this.count,
    required this.originCenter,
    required this.originSize,
    required this.originRect,
    required this.pointer,
    this.returnShrinkT,
    this.opacity = 1,
  });

  _DragVisualState copyWith({
    Offset? pointer,
    double? returnShrinkT,
    double? opacity,
  }) {
    return _DragVisualState(
      files: files,
      count: count,
      originCenter: originCenter,
      originSize: originSize,
      originRect: originRect,
      pointer: pointer ?? this.pointer,
      returnShrinkT: returnShrinkT ?? this.returnShrinkT,
      opacity: opacity ?? this.opacity,
    );
  }
}
