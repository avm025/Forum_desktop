import 'package:flutter/material.dart';

import '../models/dialogs_list_view_model.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'status_ticks.dart';

/// Строка диалога в списке чатов (высота 80).
class DialogTile extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool selected;
  final VoidCallback onTap;

  const DialogTile({
    super.key,
    required this.dialog,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onSelected = selected;
    final titleColor = onSelected ? Colors.white : p.text1;
    final subColor = onSelected ? Colors.white70 : p.text2;
    final timeColor = onSelected ? Colors.white70 : p.text2;

    final isOutgoing = dialog.last_msg_status >= 0;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 80,
        color: onSelected ? p.selectedTile : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AvatarWidget(
              name: dialog.chatName,
              avatarUrl: dialog.avatar,
              avatarColor: dialog.avatarColor,
              online: dialog.online,
              size: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dialog.chatName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (dialog.chatMuted) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.volume_off_rounded,
                            size: 15, color: subColor),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _subtitle(subColor),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOutgoing) ...[
                      StatusTicks(status: dialog.last_msg_status, size: 15),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      dialog.last_msg_dttmcr,
                      style: TextStyle(color: timeColor, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _trailingIndicator(p, onSelected),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _subtitle(Color color) {
    final showSender = dialog.isGrp &&
        dialog.last_msg_fr_name.isNotEmpty &&
        dialog.last_msg_status < 0;
    if (showSender) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dialog.last_msg_fr_name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Text(
            dialog.last_msg,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ],
      );
    }
    return Text(
      dialog.last_msg,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 14, height: 1.2),
    );
  }

  Widget _trailingIndicator(ForumPalette p, bool onSelected) {
    if (dialog.unread > 0) {
      return Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: onSelected ? Colors.white : p.text3,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          '${dialog.unread}',
          style: TextStyle(
            color: onSelected ? p.selectedTile : p.bg1,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (dialog.fav) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: onSelected ? Colors.white24 : p.bg3,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.favorite,
            size: 13, color: onSelected ? Colors.white : p.lime),
      );
    }
    if (dialog.isPinned) {
      return Icon(Icons.push_pin,
          size: 16, color: onSelected ? Colors.white70 : p.text2);
    }
    return const SizedBox(width: 20, height: 20);
  }
}
