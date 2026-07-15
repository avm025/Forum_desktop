import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Галочки статуса доставки/прочтения сообщения.
/// status: 0 — отправлено, 1 — доставлено, 2 — прочитано.
class StatusTicks extends StatelessWidget {
  final int status;
  final double size;
  final Color? color;
  final Color? readColor;

  const StatusTicks({
    super.key,
    required this.status,
    this.size = 16,
    this.color,
    this.readColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (status < -1) return const SizedBox.shrink();

    if (status == -1) {
      return Icon(Icons.schedule, size: size, color: color ?? p.text2);
    }

    final read = status >= 2;
    final tickColor = read
        ? (readColor ?? p.lime)
        : (color ?? p.text2);

    if (status == 0) {
      return Icon(Icons.check, size: size, color: tickColor);
    }

    return SizedBox(
      width: size + 5,
      height: size,
      child: Stack(
        children: [
          Icon(Icons.check, size: size, color: tickColor),
          Positioned(
            left: 5,
            child: Icon(Icons.check, size: size, color: tickColor),
          ),
        ],
      ),
    );
  }
}
