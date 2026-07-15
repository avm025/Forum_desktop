import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

/// Шапка открытой переписки.
class ChatHeader extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool showBack;

  const ChatHeader({super.key, required this.dialog, this.showBack = false});

  String get _subtitle {
    if (dialog.online) return 'в сети';
    if (dialog.isGrp) {
      final info = dialog.groupAditionalInfo;
      if (info?.desc != null && info!.desc!.isNotEmpty) return info.desc!;
      return 'группа';
    }
    return 'Был(а) недавно';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: p.bg1,
        border: Border(bottom: BorderSide(color: p.border1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: context.read<AppState>().clearSelection,
              icon: Icon(Icons.arrow_back, color: p.text1),
            ),
          AvatarWidget(
            name: dialog.chatName,
            avatarUrl: dialog.avatar,
            avatarColor: dialog.avatarColor,
            online: dialog.online,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dialog.chatName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text1,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _subtitle,
                  style: TextStyle(
                    color: dialog.online ? p.lime : p.text2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.more_horiz, color: p.text1, size: 24),
        ],
      ),
    );
  }
}
