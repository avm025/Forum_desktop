import 'package:flutter/material.dart';

import '../calls/call_message_display.dart';
import '../theme/app_theme.dart';

/// Пузырь результата звонка (iOS `CallMessageCell`).
class CallMessageBubble extends StatelessWidget {
  final CallMessageDisplay display;
  final bool onAccent;
  final double? maxWidth;
  final Widget? trailing;

  const CallMessageBubble({
    super.key,
    required this.display,
    this.onAccent = false,
    this.maxWidth,
    this.trailing,
  });

  static const _iconSize = 40.0;
  static const Color _talkGreen = Color(0xFF0FBE00);
  static const Color _failRed = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = display.body;
    final failed = body.isFailed;
    final iconBg = failed ? _failRed : _talkGreen;
    final icon = body.isVideo
        ? (failed ? Icons.videocam_off_rounded : Icons.videocam_rounded)
        : (failed ? Icons.call_end_rounded : Icons.phone_rounded);

    final titleColor = onAccent ? Colors.white : p.text1;
    final subtitleColor = onAccent ? Colors.white70 : p.text2;

    return ConstrainedBox(
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : const BoxConstraints(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _iconSize,
            height: _iconSize,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            fit: FlexFit.loose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  display.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if (display.subtitle.trim().isNotEmpty)
                  Text(
                    display.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
