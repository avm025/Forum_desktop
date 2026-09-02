import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_type.dart';
import '../models/dialogs_list_view_model.dart';
import '../screens/peer_profile/peer_profile_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

/// Шапка открытой переписки.
class ChatHeader extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool showBack;
  final VoidCallback? onSearch;

  const ChatHeader({
    super.key,
    required this.dialog,
    this.showBack = false,
    this.onSearch,
  });

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

  void _openPeerProfile(BuildContext context) {
    if (dialog.fav) return;
    final id = dialog.id?.trim() ?? '';
    if (id.isEmpty || id == '0') return;
    PeerProfileScreen.open(context, dialog);
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeader = constraints.maxWidth < 380;
          return Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: context.read<AppState>().clearSelection,
                  icon: Icon(Icons.arrow_back, color: p.text1),
                ),
              Expanded(
                child: InkWell(
                  onTap: () => _openPeerProfile(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
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
                          mainAxisSize: MainAxisSize.min,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canCall && !compactHeader) ...[
                if (_isGroup) ...[
                  IconButton(
                    tooltip: 'Групповой аудиозвонок',
                    onPressed: () => context
                        .read<AppState>()
                        .startCallFromChat(video: false),
                    icon: Icon(Icons.groups_outlined, color: p.text1, size: 24),
                  ),
                  IconButton(
                    tooltip: 'Групповой видеозвонок',
                    onPressed: () => context
                        .read<AppState>()
                        .startCallFromChat(video: true),
                    icon: Icon(
                      Icons.video_call_outlined,
                      color: p.text1,
                      size: 26,
                    ),
                  ),
                ] else ...[
                  IconButton(
                    tooltip: 'Аудиозвонок',
                    onPressed: () => context
                        .read<AppState>()
                        .startCallFromChat(video: false),
                    icon: Icon(Icons.call, color: p.text1, size: 22),
                  ),
                  IconButton(
                    tooltip: 'Видеозвонок',
                    onPressed: () => context
                        .read<AppState>()
                        .startCallFromChat(video: true),
                    icon: Icon(Icons.videocam_outlined, color: p.text1, size: 24),
                  ),
                ],
              ],
              IconButton(
                tooltip: 'Поиск',
                onPressed: onSearch,
                icon: Icon(Icons.search_rounded, color: p.text1, size: 24),
              ),
              IconButton(
                tooltip: 'Профиль',
                onPressed: () => _openPeerProfile(context),
                icon: Icon(Icons.more_horiz, color: p.text1, size: 24),
              ),
            ],
          );
        },
      ),
    );
  }
}
