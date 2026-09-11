import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/chat_file_dnd.dart';
import 'live_geo_map.dart';
import 'location_map_dialog.dart';

/// Превью геопозиции: короткий ЛКМ — карта; сдвиг — сразу DnD без открытия.
/// При перетаскивании — превью карты с зелёным «+», как у медиа.
class LocationPreview extends StatefulWidget {
  final MessageViewModel message;
  final double? maxWidth;
  final void Function(Offset globalPosition)? onContextMenu;

  const LocationPreview({
    super.key,
    required this.message,
    this.maxWidth,
    this.onContextMenu,
  });

  static const double mapHeight = 180;

  @override
  State<LocationPreview> createState() => LocationPreviewState();
}

class LocationPreviewState extends State<LocationPreview> {
  final GlobalKey _mapBoundaryKey = GlobalKey();
  final GlobalKey<DragItemWidgetState> _dragKey =
      GlobalKey<DragItemWidgetState>();

  Offset? _downPos;
  bool _dragArmed = false;
  bool _suppressOpen = false;
  Timer? _longPressTimer;

  static const _longPressDuration = Duration(milliseconds: 350);
  static const _dragSlop = 10.0;
  static const _plusSize = 30.0;
  static const _plusIconSize = 18.0;
  static const _telegramPlusGreen = Color(0xFF31B545);

  MessageViewModel get message => widget.message;

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

  Widget _dragPreview(BuildContext context, Widget child) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        child,
        _plusBadge(),
      ],
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  Future<Uint8List?> captureMapPng() async {
    final ctx = _mapBoundaryKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<String?> captureMapToTempFile() async {
    final png = await captureMapPng();
    if (png == null || png.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/forum_geo');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final name =
        'map_${message.id.trim().isNotEmpty ? message.id.trim() : DateTime.now().millisecondsSinceEpoch}.png';
    final path = '${folder.path}/$name';
    await File(path).writeAsBytes(png, flush: true);
    return path;
  }

  void _openMap(BuildContext context) {
    final lat = message.latitude;
    final lon = message.longitude;
    if (lat == null || lon == null) return;
    final address = (message.address ?? '').trim();
    final dialogId = context.read<AppState>().selectedId ?? '';
    LocationMapDialog.show(
      context,
      messageId: message.id,
      dialogId: dialogId,
      latitude: lat,
      longitude: lon,
      address: address.isNotEmpty ? address : null,
      live: message.locationLive,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    AttachmentSelection.retainPointer();
    _downPos = e.position;
    _dragArmed = false;
    _suppressOpen = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (!mounted || _downPos == null) return;
      _dragArmed = true;
      _suppressOpen = true;
      AttachmentSelection.suppressNextBubbleTap();
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final start = _downPos;
    if (start == null) return;
    if (!_suppressOpen && (e.position - start).distance >= _dragSlop) {
      _longPressTimer?.cancel();
      _suppressOpen = true;
      _dragArmed = true;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    final suppressOpen = _suppressOpen || _dragArmed;
    _downPos = null;
    _dragArmed = false;
    _suppressOpen = false;

    if (suppressOpen) {
      AttachmentSelection.suppressNextBubbleTap();
      return;
    }

    if (message.latitude != null && message.longitude != null) {
      AttachmentSelection.suppressNextBubbleTap();
      _openMap(context);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    setState(() {
      _downPos = null;
      _dragArmed = false;
      _suppressOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lat = message.latitude;
    final lon = message.longitude;
    final address = (message.address ?? '').trim();
    final width = (widget.maxWidth ?? 240).clamp(180.0, 320.0);
    final live = message.locationLive;
    final title = address.isNotEmpty
        ? address
        : (lat != null && lon != null)
            ? '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'
            : 'Геопозиция';

    final mapChild = SizedBox(
      height: LocationPreview.mapHeight,
      width: width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (lat != null && lon != null)
            LiveGeoMap(
              latitude: lat,
              longitude: lon,
              followLive: live,
              zoom: 16,
              fallbackColor: const Color(0xFF2A332A),
            )
          else
            const _MapFallback(),
          if (live)
            const Positioned(
              left: 8,
              top: 8,
              child: _LiveBadge(),
            ),
        ],
      ),
    );

    final card = Material(
      color: Colors.transparent,
      child: GestureDetector(
        onSecondaryTapUp: (details) {
          AttachmentSelection.suppressNextBubbleTap();
          widget.onContextMenu?.call(details.globalPosition);
        },
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RepaintBoundary(
                    key: _mapBoundaryKey,
                    child: mapChild,
                  ),
                  ColoredBox(
                    color: p.bg1.withValues(alpha: 0.55),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text1,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          if (address.isNotEmpty &&
                              lat != null &&
                              lon != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                                style: TextStyle(
                                  color: p.text2,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
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

    if (!ChatFileDnd.isSupported || lat == null || lon == null) {
      return card;
    }

    return DragItemWidget(
      key: _dragKey,
      allowedOperations: () => [DropOperation.copy],
      liftBuilder: _dragPreview,
      dragBuilder: _dragPreview,
      dragItemProvider: (request) async {
        final path = await captureMapToTempFile();
        if (path == null) return null;
        final item = DragItem(
          suggestedName: 'map.png',
          localData: 'forum-file-geo-${message.id}',
        );
        item.add(Formats.fileUri(Uri.file(path)));
        return item;
      },
      child: DraggableWidget(
        isLocationDraggable: (_) => true,
        child: card,
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC1B1B1B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me, size: 12, color: Color(0xFF9BFF4B)),
          SizedBox(width: 4),
          Text(
            'Live',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFallback extends StatelessWidget {
  const _MapFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3A4A3A), Color(0xFF1C2A1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.map_outlined, color: Color(0x889BFF4B), size: 36),
      ),
    );
  }
}
