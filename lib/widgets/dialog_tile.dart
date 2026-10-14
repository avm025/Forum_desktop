import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'status_ticks.dart';

/// Строка диалога в списке чатов (высота 80).
class DialogTile extends StatelessWidget {
  final DialogsListViewModel dialog;
  final bool selected;
  final bool dropHover;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;
  final bool selectMode;
  final bool checked;

  const DialogTile({
    super.key,
    required this.dialog,
    required this.selected,
    required this.onTap,
    this.onContextMenu,
    this.dropHover = false,
    this.selectMode = false,
    this.checked = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final draft = state.composerDraftPreview(dialog.id);
    final lastMsg = state.mentionDisplayText(
      dialog.last_msg,
      dlgId: dialog.id,
    );
    final emphasized = !selectMode && (selected || dropHover);
    final titleColor = emphasized ? Colors.white : p.text1;
    final subColor = emphasized ? Colors.white70 : p.text2;
    final timeColor = emphasized ? Colors.white70 : p.text2;
    final draftLabelColor = emphasized ? Colors.white : p.purple;

    // Как Telegram: при черновике галочки последнего исходящего не показываем.
    // status >= -1: отправляется / отправлено / доставлено / прочитано.
    final isOutgoing = draft == null && dialog.last_msg_status >= -1;
    final bg = selectMode
        ? Colors.transparent
        : dropHover
            ? p.purple.withValues(alpha: 0.85)
            : (selected ? p.selectedTile : Colors.transparent);

    return GestureDetector(
      onSecondaryTapUp: onContextMenu == null
          ? null
          : (details) => onContextMenu!(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: ColoredBox(
        color: bg,
        child: SizedBox(
          height: 80,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (selectMode) ...[
                      _SelectCircle(checked: checked, purple: p.purple),
                      const SizedBox(width: 12),
                    ],
                    AvatarWidget(
                      name: dialog.chatName,
                      avatarUrl: dialog.avatar,
                      avatarColor: dialog.avatarColor,
                      colAvaId: dialog.colAvaId,
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
                          _subtitle(
                            subColor,
                            draft: draft,
                            draftLabelColor: draftLabelColor,
                            lastMsg: lastMsg,
                            previewLoading:
                                state.isDialogPreviewHydrating(dialog.id) ||
                                    (selected &&
                                        state.isDialogHistoryLoading(
                                          dialog.id,
                                        )),
                          ),
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
                            Text(
                              dialog.last_msg_dttmcr,
                              style:
                                  TextStyle(color: timeColor, fontSize: 13),
                            ),
                            if (isOutgoing) ...[
                              const SizedBox(width: 4),
                              StatusTicks(
                                  status: dialog.last_msg_status, size: 15),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (!selectMode) _trailingIndicator(p, emphasized),
                      ],
                    ),
                  ],
                ),
              ),
              // Как Telegram: тонкий разделитель после аватара.
              Positioned(
                left: selectMode ? 16 + 22 + 12 + 52 + 12 : 16 + 52 + 12,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: emphasized
                      ? Colors.white.withValues(alpha: 0.12)
                      : p.border1,
                  child: const SizedBox(height: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _subtitle(
    Color color, {
    String? draft,
    required Color draftLabelColor,
    required String lastMsg,
    bool previewLoading = false,
  }) {
    if (draft != null && draft.isNotEmpty) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Черновик: ',
              style: TextStyle(
                color: draftLabelColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: draft,
              style: TextStyle(color: color, fontSize: 14),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (lastMsg.trim().isEmpty && previewLoading) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Загрузка…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ],
      );
    }

    // В каналах не показываем имя канала второй строкой (это не «отправитель»).
    final showSender = dialog.isGrp &&
        !dialog.isCh &&
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
            lastMsg,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ],
      );
    }
    return Text(
      lastMsg,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 14, height: 1.2),
    );
  }

  Widget _trailingIndicator(ForumPalette p, bool onSelected) {
    if (dialog.unread > 0) {
      final accent = dialog.hasTagged;
      final badgeBg = onSelected
          ? Colors.white
          : (accent ? p.purple : p.text3);
      final badgeFg = onSelected ? p.selectedTile : p.bg1;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accent) ...[
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: badgeBg,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '@',
                style: TextStyle(
                  color: badgeFg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '${dialog.unread}',
              style: TextStyle(
                color: badgeFg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

class _SelectCircle extends StatelessWidget {
  final bool checked;
  final Color purple;

  const _SelectCircle({required this.checked, required this.purple});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? purple : Colors.transparent,
        border: Border.all(
          color: checked ? purple : purple.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}
