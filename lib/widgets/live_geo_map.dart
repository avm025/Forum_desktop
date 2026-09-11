import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Плиточная карта с плавным следованием за точкой (геотрансляция).
class LiveGeoMap extends StatefulWidget {
  final double latitude;
  final double longitude;
  final bool followLive;
  final int zoom;
  final Color? fallbackColor;

  const LiveGeoMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.followLive = false,
    this.zoom = 16,
    this.fallbackColor,
  });

  @override
  State<LiveGeoMap> createState() => _LiveGeoMapState();
}

class _LiveGeoMapState extends State<LiveGeoMap>
    with TickerProviderStateMixin {
  static const double _tilePx = 256;
  static const _sub = ['a', 'b', 'c', 'd'];

  late final AnimationController _move;
  late final AnimationController _pulse;
  late double _fromLat;
  late double _fromLon;
  late double _toLat;
  late double _toLon;

  @override
  void initState() {
    super.initState();
    _fromLat = widget.latitude;
    _fromLon = widget.longitude;
    _toLat = widget.latitude;
    _toLon = widget.longitude;
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.followLive) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant LiveGeoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = widget.latitude != oldWidget.latitude ||
        widget.longitude != oldWidget.longitude;
    if (moved) {
      if (widget.followLive) {
        _fromLat = _displayLat;
        _fromLon = _displayLon;
        _toLat = widget.latitude;
        _toLon = widget.longitude;
        _move.forward(from: 0);
      } else {
        _fromLat = widget.latitude;
        _fromLon = widget.longitude;
        _toLat = widget.latitude;
        _toLon = widget.longitude;
        _move.value = 1;
      }
    }
    if (widget.followLive && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.followLive && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  double get _t => Curves.easeOutCubic.transform(_move.value);

  double get _displayLat => _fromLat + (_toLat - _fromLat) * _t;

  double get _displayLon => _fromLon + (_toLon - _fromLon) * _t;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_move, _pulse]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            if (w <= 0 || h <= 0) return const SizedBox.expand();
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: widget.fallbackColor ?? const Color(0xFFE6E2D6),
                ),
                ClipRect(
                  child: _tiles(w, h),
                ),
                Center(child: _Pin(pulse: widget.followLive ? _pulse.value : 0)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _tiles(double w, double h) {
    final z = widget.zoom.clamp(1, 19);
    final cx = _lonToX(_displayLon, z);
    final cy = _latToY(_displayLat, z);
    final centerTx = cx.floor();
    final centerTy = cy.floor();
    final fracX = cx - centerTx;
    final fracY = cy - centerTy;
    final n = 1 << z;

    final radiusX = ((w / 2) / _tilePx).ceil() + 1;
    final radiusY = ((h / 2) / _tilePx).ceil() + 1;
    final children = <Widget>[];
    for (var dy = -radiusY; dy <= radiusY; dy++) {
      for (var dx = -radiusX; dx <= radiusX; dx++) {
        final tx = (centerTx + dx) % n;
        final wrappedX = tx < 0 ? tx + n : tx;
        final ty = centerTy + dy;
        if (ty < 0 || ty >= n) continue;
        final left = w / 2 - fracX * _tilePx + dx * _tilePx;
        final top = h / 2 - fracY * _tilePx + dy * _tilePx;
        children.add(
          Positioned(
            left: left,
            top: top,
            width: _tilePx,
            height: _tilePx,
            child: CachedNetworkImage(
              imageUrl: _tileUrl(wrappedX, ty, z),
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => const ColoredBox(
                color: Color(0xFFE6E2D6),
              ),
              errorWidget: (_, __, ___) => const ColoredBox(
                color: Color(0xFFE6E2D6),
              ),
            ),
          ),
        );
      }
    }
    return Stack(children: children);
  }

  static String _tileUrl(int x, int y, int z) {
    final host = _sub[(x + y) % _sub.length];
    return 'https://$host.basemaps.cartocdn.com/rastertiles/voyager/'
        '$z/$x/$y@2x.png';
  }

  static double _lonToX(double lon, int zoom) {
    return (lon + 180.0) / 360.0 * (1 << zoom);
  }

  static double _latToY(double lat, int zoom) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final latRad = clamped * math.pi / 180;
    return (1 -
            math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2 *
        (1 << zoom);
  }
}

class _Pin extends StatelessWidget {
  final double pulse;

  const _Pin({required this.pulse});

  static const _fill = Color(0xFF9BFF4B);
  static const _border = Color(0xFF69CD19);

  @override
  Widget build(BuildContext context) {
    final ring = 10 + pulse * 10;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (pulse > 0)
            Container(
              width: ring,
              height: ring,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _fill.withValues(alpha: 0.22 * (1 - pulse * 0.35)),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: _border, width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: const Size(10, 10),
                painter: _PinStemPainter(_border),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinStemPainter extends CustomPainter {
  final Color color;
  _PinStemPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PinStemPainter oldDelegate) =>
      oldDelegate.color != color;
}
