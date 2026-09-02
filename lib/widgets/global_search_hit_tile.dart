import 'package:flutter/material.dart';

import '../models/global_search_hit.dart';
import '../models/global_search_scope.dart';
import '../theme/app_theme.dart';
import '../utils/media_file_url.dart';
import 'avatar_widget.dart';
import 'cached_forum_image.dart';

class GlobalSearchHitTile extends StatelessWidget {
  final GlobalSearchHit hit;
  final bool selected;
  final VoidCallback onTap;
  final bool hideChatInSubtitle;

  const GlobalSearchHitTile({
    super.key,
    required this.hit,
    required this.selected,
    required this.onTap,
    this.hideChatInSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final emphasized = selected;
    final titleColor = emphasized ? Colors.white : p.text1;
    final subColor = emphasized ? Colors.white70 : p.text2;
    final bg = selected ? p.selectedTile : Colors.transparent;
    final subtitle = hideChatInSubtitle
        ? (hit.message.dtshow.isNotEmpty ? hit.message.dtshow : hit.subtitle)
        : hit.subtitle;

    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: ColoredBox(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _Leading(scope: hit.scope, hit: hit),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  final GlobalSearchScope scope;
  final GlobalSearchHit hit;

  const _Leading({required this.scope, required this.hit});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dialog = hit.dialog;
    final file = hit.file;

    if (scope == GlobalSearchScope.voice) {
      return _RoundIcon(icon: Icons.mic_rounded, color: p.purple);
    }

    if (file != null &&
        (scope == GlobalSearchScope.photos || scope == GlobalSearchScope.videos)) {
      final url = file.preview.trim().isNotEmpty
          ? file.preview
          : MediaFileUrl.resolve(file);
      if (url.trim().isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: CachedForumImage(url: url, fit: BoxFit.cover),
          ),
        );
      }
    }

    final icon = switch (scope) {
      GlobalSearchScope.photos => Icons.image_outlined,
      GlobalSearchScope.videos => Icons.videocam_outlined,
      GlobalSearchScope.files => Icons.insert_drive_file_outlined,
      GlobalSearchScope.voice => Icons.mic_rounded,
      GlobalSearchScope.chats => Icons.chat_bubble_outline_rounded,
    };

    if (scope == GlobalSearchScope.files) {
      return _RoundIcon(icon: icon, color: p.lime);
    }

    return AvatarWidget(
      name: dialog.chatName,
      avatarUrl: dialog.avatar,
      avatarColor: dialog.avatarColor,
      colAvaId: dialog.colAvaId,
      size: 48,
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _RoundIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
