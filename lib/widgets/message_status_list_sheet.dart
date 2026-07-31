import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/msg_read_entry.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/msg_read_display.dart';
import 'avatar_widget.dart';
import 'status_ticks.dart';

/// Список «кто прочитал» (iOS `MessageStatusListViewController`).
class MessageStatusListSheet extends StatelessWidget {
  final List<MsgReadEntry> entries;

  const MessageStatusListSheet({super.key, required this.entries});

  static Future<void> show(
    BuildContext context, {
    required List<MsgReadEntry> entries,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MessageStatusListSheet(entries: entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: p.bg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Назад',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18, color: p.purple),
                      ),
                      Expanded(
                        child: Text(
                          MsgReadDisplay.viewsLabel(entries.length),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Divider(height: 1, color: p.border1),
                Flexible(
                  child: entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Нет просмотров',
                            style: TextStyle(color: p.text2, fontSize: 15),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => Padding(
                            padding: const EdgeInsets.only(left: 70),
                            child: Divider(height: 1, color: p.border1),
                          ),
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            final colors = _avatarColors(
                              state,
                              e.colAvaId,
                            );
                            return ListTile(
                              leading: AvatarWidget(
                                name: e.name.isNotEmpty ? e.name : '?',
                                avatarUrl: e.avatarUrl,
                                avatarColor: colors,
                                size: 40,
                              ),
                              title: Text(
                                e.name.isNotEmpty ? e.name : e.usrId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.text1,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusTicks(
                                    status: 2,
                                    size: 14,
                                    readColor: p.lime,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    MsgReadDisplay.formatReadAt(e.dttmcr),
                                    style: TextStyle(
                                      color: p.text2,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<String>? _avatarColors(AppState state, int? colAvaId) {
    if (colAvaId == null) return null;
    final palette = state.database.avatarById(colAvaId);
    if (palette == null) return null;
    return palette
        .hexForDark(state.isDark)
        .map((h) => h.startsWith('#') ? h : '#$h')
        .toList();
  }
}
