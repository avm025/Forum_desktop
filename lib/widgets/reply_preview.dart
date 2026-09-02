import 'package:flutter/material.dart';

import '../models/message_view_model.dart';
import '../theme/app_theme.dart';
import 'media_thumb_tile.dart';

/// Полоса цитаты при ответе или пересылке — как AnswerMessage / Figma.
class ReplyPreview extends StatelessWidget {
  final MessageViewModel message;
  final bool onAccent;
  final double? maxWidth;
  final VoidCallback? onTap;
  final String? currentUserId;

  const ReplyPreview({
    super.key,
    required this.message,
    this.onAccent = false,
    this.maxWidth,
    this.onTap,
    this.currentUserId,
  });

  static const _textHeight = 40.0;
  static const _mediaHeight = 56.0;
  static const _radius = 5.0;
  static const _stripeWidth = 2.0;
  static const _thumbSize = 28.0;

  bool get _isRepost => message.repost;

  double get _height {
    if (_isRepost && message.replyShowsMediaThumb) return _mediaHeight;
    return _textHeight;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final preview =
        _isRepost ? '' : message.replyPreviewTextFor(currentUserId);
    final name = message.prn_fr_name.trim().isNotEmpty
        ? message.prn_fr_name.trim()
        : 'Сообщение';

    final bgColor = onAccent
        ? Colors.white.withValues(alpha: 0.10)
        : p.purple.withValues(alpha: 0.12);
    final stripeColor = onAccent
        ? Colors.white.withValues(alpha: 0.50)
        : p.purple.withValues(alpha: 0.35);
    final nameColor = onAccent ? p.lime : p.purple;
    final textColor = onAccent ? Colors.white.withValues(alpha: 0.85) : p.text2;
    final headerColor = onAccent
        ? Colors.white.withValues(alpha: 0.70)
        : p.text2;

    final textMaxWidth = maxWidth != null
        ? (maxWidth! -
            _stripeWidth -
            (_isRepost && message.replyShowsMediaThumb ? _thumbSize + 8 : 0) -
            (!_isRepost && message.replyShowsMediaThumb ? _thumbSize + 8 : 0) -
            16)
        : 220.0;

    final bar = Container(
      height: _height,
      margin: const EdgeInsets.only(bottom: 6),
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : null,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: _stripeWidth, color: stripeColor),
          if (_isRepost && message.replyShowsMediaThumb) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaThumbTile(
                file: message.prn_firstFile!,
                width: _thumbSize,
                height: _thumbSize,
                fit: BoxFit.cover,
              ),
            ),
          ] else if (!_isRepost && message.replyShowsMediaThumb) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaThumbTile(
                file: message.prn_firstFile!,
                width: _thumbSize,
                height: _thumbSize,
                fit: BoxFit.cover,
              ),
            ),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: textMaxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isRepost)
                    Text(
                      'Переслано от',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: headerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return bar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: bar,
    );
  }
}
