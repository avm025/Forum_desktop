import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_type.dart';
import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

/// Шапка открытой переписки.
class ChatHeader extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool showBack;

  const ChatHeader({super.key, required this.dialog, this.showBack = false});

  bool get _isGroup =>
      dialog.isGrp || dialog.chatType == ChatType.groupChat;

  String get _subtitle {
    if (dialog.online) return 'в сети';
    if (_isGroup) {
      final info = dialog.groupAditionalInfo;
      if (info?.desc != null && info!.desc!.isNotEmpty) return info.desc!;
      return 'группа';
    }
    return 'Был(а) недавно';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final typing = state.chatTypingLabel;
    final subtitle = (typing != null && typing.isNotEmpty) ? typing : _subtitle;
    final subtitleColor = typing != null && typing.isNotEmpty
        ? p.purple
        : (dialog.online ? p.lime : p.text2);
    final canCall = !dialog.fav &&
        (_isGroup || (dialog.usr_id?.trim().isNotEmpty ?? false));

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
            colAvaId: dialog.colAvaId,
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
                  subtitle,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (canCall) ...[
            if (_isGroup) ...[
              IconButton(
                tooltip: 'Групповой аудиозвонок',
                onPressed: () =>
                    context.read<AppState>().startCallFromChat(video: false),
                icon: Icon(Icons.groups_outlined, color: p.text1, size: 24),
              ),
              IconButton(
                tooltip: 'Групповой видеозвонок',
                onPressed: () =>
                    context.read<AppState>().startCallFromChat(video: true),
                icon: Icon(Icons.video_call_outlined, color: p.text1, size: 26),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Аудиозвонок',
                onPressed: () =>
                    context.read<AppState>().startCallFromChat(video: false),
                icon: Icon(Icons.call, color: p.text1, size: 22),
              ),
              IconButton(
                tooltip: 'Видеозвонок',
                onPressed: () =>
                    context.read<AppState>().startCallFromChat(video: true),
                icon: Icon(Icons.videocam_outlined, color: p.text1, size: 24),
              ),
            ],
          ],
          Icon(Icons.more_horiz, color: p.text1, size: 24),
        ],
      ),
    );
  }
}
