import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_config.dart';
import '../../calls/call_manager.dart';
import '../../calls/call_models.dart';
import '../../models/chat_type.dart';
import '../../models/dialogs_list_view_model.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/reaction_utils.dart';
import '../avatar_widget.dart';

/// Панель выбора контактов поверх экрана звонка.
///
/// Рендерится в `MaterialApp.builder` вне Navigator/Overlay — без Tooltip
/// и с явной высотой (иначе Expanded раздувает layout).
class CallInviteSheet extends StatefulWidget {
  const CallInviteSheet({super.key});

  @override
  State<CallInviteSheet> createState() => _CallInviteSheetState();
}

class _CallInviteSheetState extends State<CallInviteSheet> {
  final _selected = <String, CallParticipant>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.watch<AppState>();
    final calls = context.watch<CallManager>();
    final session = calls.session;
    final myId = app.profile?.id.trim() ?? '';
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final inCall = <String>{
      if (myId.isNotEmpty) myId,
      ...?session?.peers.map((e) => e.userId.trim()),
    };

    final candidates = app.allDialogs
        .where((d) => !d.fav)
        .where((d) => !d.isGrp && d.chatType != ChatType.groupChat)
        .where((d) {
          final uid = d.usr_id?.trim() ?? '';
          if (uid.isEmpty) return false;
          if (myId.isNotEmpty && ReactionUtils.sameUserId(uid, myId)) {
            return false;
          }
          return !inCall.any((id) => ReactionUtils.sameUserId(id, uid));
        })
        .where((d) {
          if (_query.trim().isEmpty) return true;
          final q = _query.trim().toLowerCase();
          return d.chatName.toLowerCase().contains(q) ||
              (d.phone?.toLowerCase().contains(q) ?? false);
        })
        .toList()
      ..sort(
        (a, b) => a.chatName.toLowerCase().compareTo(b.chatName.toLowerCase()),
      );

    final panelHeight = math.min(size.height * 0.72, size.height - 48);
    final panelWidth = math.min(480.0, size.width - 24);

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: SizedBox(
              height: panelHeight,
              width: panelWidth,
              child: Material(
                color: p.bg2,
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.text2.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Пригласить участников',
                              style: TextStyle(
                                color: p.text1,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          // Без IconButton.tooltip — вне Overlay он падает.
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: calls.closeInvitePicker,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(Icons.close, color: p.text2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(color: p.text1),
                        decoration: InputDecoration(
                          hintText: 'Поиск',
                          hintStyle: TextStyle(color: p.text2),
                          prefixIcon: Icon(Icons.search, color: p.text2),
                          filled: true,
                          fillColor: p.bg1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: candidates.isEmpty
                          ? Center(
                              child: Text(
                                'Нет доступных контактов',
                                style: TextStyle(color: p.text2),
                              ),
                            )
                          : ListView.builder(
                              itemCount: candidates.length,
                              itemBuilder: (context, i) {
                                final d = candidates[i];
                                final id = d.usr_id!.trim();
                                return _CandidateTile(
                                  dialog: d,
                                  selected: _selected.containsKey(id),
                                  onToggle: () {
                                    setState(() {
                                      if (_selected.containsKey(id)) {
                                        _selected.remove(id);
                                      } else {
                                        _selected[id] = CallParticipant(
                                          userId: id,
                                          name: d.chatName,
                                          avatarUrl: ApiConfig.resolveAssetUrl(
                                            d.avatar,
                                          ),
                                        );
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 12),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor:
                              p.purple.withValues(alpha: 0.35),
                        ),
                        onPressed: _selected.isEmpty
                            ? null
                            : () => calls.inviteParticipants(
                                  _selected.values.toList(),
                                ),
                        child: Text(
                          _selected.isEmpty
                              ? 'Выберите участников'
                              : 'Пригласить (${_selected.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool selected;
  final VoidCallback onToggle;

  const _CandidateTile({
    required this.dialog,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        onTap: onToggle,
        leading: AvatarWidget(
          name: dialog.chatName,
          avatarUrl: dialog.avatar,
          avatarColor: dialog.avatarColor,
          online: dialog.online,
          size: 40,
        ),
        title: Text(
          dialog.chatName,
          style: TextStyle(
            color: p.text1,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: dialog.online
            ? Text('в сети', style: TextStyle(color: p.lime, fontSize: 12))
            : null,
        trailing: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          color: selected ? p.purple : p.text2,
        ),
      ),
    );
  }
}
