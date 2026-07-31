import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'media_thumb_tile.dart';

/// Полоса «ответ на …» над полем ввода (Figma: инпуты сообщений с цитатой).
class MessageComposerReply extends StatelessWidget {
  final MessageViewModel message;
  final VoidCallback onClose;

  const MessageComposerReply({
    super.key,
    required this.message,
    required this.onClose,
  });

  static const _height = 40.0;
  static const _radius = 5.0;
  static const _stripeWidth = 2.0;
  static const _thumbSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final me = context.watch<AppState>().profile?.id;
    final preview = message.quotedPreviewTextFor(me);
    final name = message.quotedAuthorName.isNotEmpty
        ? message.quotedAuthorName
        : 'Сообщение';

    return Container(
      height: _height,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: p.purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: _stripeWidth, color: p.purple.withValues(alpha: 0.35)),
          if (message.quotedShowsMediaThumb) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaThumbTile(
                file: message.quotedFirstFile!,
                width: _thumbSize,
                height: _thumbSize,
                fit: BoxFit.cover,
              ),
            ),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.purple,
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
                        color: p.text2,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, size: 18, color: p.text2),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
