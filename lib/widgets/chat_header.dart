import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_type.dart';
import '../models/dialogs_list_view_model.dart';
import '../screens/peer_profile/peer_profile_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

/// Шапка открытой переписки.
class ChatHeader extends StatefulWidget {
  final DialogsListViewModel dialog;
  final bool showBack;
  final VoidCallback? onSearch;

  const ChatHeader({
    super.key,
    required this.dialog,
    this.showBack = false,
    this.onSearch,
  });

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader> {
  int _memberCount = 0;
  int _onlineCount = 0;
  String? _loadedDlgId;

  DialogsListViewModel get dialog => widget.dialog;

  bool get _isGroup =>
      dialog.isGrp || dialog.chatType == ChatType.groupChat;

  @override
  void initState() {
    super.initState();
    _scheduleMembersSync();
  }

  @override
  void didUpdateWidget(ChatHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialog.id != widget.dialog.id) {
      _memberCount = 0;
      _onlineCount = 0;
      _loadedDlgId = null;
      _scheduleMembersSync();
    }
  }

  void _scheduleMembersSync() {
    if (!_isGroup) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncMembers());
    });
  }

  Future<void> _syncMembers() async {
    if (!_isGroup || !mounted) return;
    final id = dialog.id?.trim() ?? '';
    if (id.isEmpty || DialogsListViewModel.isPlaceholderDlgId(id)) return;

    final state = context.read<AppState>();
    void applyLocal() {
      final members = state.groupMembers(id);
      if (members.isEmpty) return;
      final total = members.length;
      final online = members.where((m) => m.online).length;
      if (_loadedDlgId == id &&
          _memberCount == total &&
          _onlineCount == online) {
        return;
      }
      setState(() {
        _loadedDlgId = id;
        _memberCount = total;
        _onlineCount = online;
      });
    }

    applyLocal();
    await state.ensureGroupMembers(id);
    if (!mounted) return;
    applyLocal();
  }

  static String _membersWord(int total) {
    final n = total % 100;
    final n1 = total % 10;
    if (n >= 11 && n <= 14) return 'участников';
    return switch (n1) {
      1 => 'участник',
      2 || 3 || 4 => 'участника',
      _ => 'участников',
    };
  }

  String _subtitleFor(AppState state) {
    if (state.connectionStatus != ConnectionStatus.connected) {
      return 'соединение';
    }
    if (!_isGroup && dialog.online) return 'в сети';
    if (_isGroup) {
      if (_memberCount > 0) {
        return '$_memberCount ${_membersWord(_memberCount)}, '
            '$_onlineCount в сети';
      }
      return 'группа';
    }
    return 'был(а) недавно';
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
    final connecting = state.connectionStatus != ConnectionStatus.connected;
    final baseSubtitle = _subtitleFor(state);
    final subtitle = (!connecting && typing != null && typing.isNotEmpty)
        ? typing
        : baseSubtitle;
    final subtitleColor = connecting
        ? p.text2
        : (typing != null && typing.isNotEmpty
            ? p.purple
            : (!_isGroup && dialog.online ? p.lime : p.text2));
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
              if (widget.showBack)
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
                    icon:
                        Icon(Icons.videocam_outlined, color: p.text1, size: 24),
                  ),
                ],
              ],
              IconButton(
                tooltip: 'Поиск',
                onPressed: widget.onSearch,
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
