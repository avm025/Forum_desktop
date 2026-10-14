import 'package:flutter/material.dart';

/// Круговой индикатор загрузки медиа в стиле Telegram:
/// тёмный круг + белое кольцо, при известном прогрессе — проценты.
class TelegramMediaLoadingOverlay extends StatelessWidget {
  /// `0…1` или `null` (бесконечный спиннер).
  final double? progress;
  final double size;

  const TelegramMediaLoadingOverlay({
    super.key,
    this.progress,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final known = p != null && p.isFinite && p >= 0;
    final value = known ? p.clamp(0.0, 1.0) : null;

    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
            SizedBox(
              width: size * 0.78,
              height: size * 0.78,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 2.6,
                strokeCap: StrokeCap.round,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            if (value != null)
              Text(
                '${(value * 100).round()}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: size >= 52 ? 13 : 11,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Превью (если есть) + затемнение + [TelegramMediaLoadingOverlay].
class TelegramMediaLoadingStack extends StatelessWidget {
  final Widget? background;
  final double? progress;
  final double loaderSize;

  const TelegramMediaLoadingStack({
    super.key,
    this.background,
    this.progress,
    this.loaderSize = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (background != null)
          background!
        else
          SizedBox(width: loaderSize * 4, height: loaderSize * 3),
        const Positioned.fill(
          child: ColoredBox(color: Color(0x40000000)),
        ),
        TelegramMediaLoadingOverlay(
          progress: progress,
          size: loaderSize,
        ),
      ],
    );
  }
}
