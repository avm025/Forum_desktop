import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Результат диалога удаления сообщения.
class DeleteMessageResult {
  final bool forEveryone;

  const DeleteMessageResult({required this.forEveryone});
}

/// Диалог удаления в стиле Telegram Desktop: подтверждение и опция «у собеседника».
Future<DeleteMessageResult?> showDeleteMessageDialog({
  required BuildContext context,
  required bool isOwnMessage,
  required bool isGroupChat,
  String? peerName,
}) {
  final p = context.palette;
  var forEveryone = false;

  final peerLabel = _peerLabel(isGroupChat: isGroupChat, peerName: peerName);

  return showDialog<DeleteMessageResult>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: p.bg2,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p.border1.withValues(alpha: 0.55)),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              'Удалить сообщение?',
              style: TextStyle(
                color: p.text1,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
              child: isOwnMessage
                  ? InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => forEveryone = !forEveryone),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: forEveryone,
                              onChanged: (value) =>
                                  setState(() => forEveryone = value ?? false),
                              activeColor: p.purple,
                              side: BorderSide(color: p.text3),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                peerLabel,
                                style: TextStyle(
                                  color: p.text1,
                                  fontSize: 15,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Сообщение будет удалено только у вас.',
                        style: TextStyle(
                          color: p.text2,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'Отмена',
                  style: TextStyle(color: p.text2, fontSize: 15),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  DeleteMessageResult(
                    forEveryone: isOwnMessage && forEveryone,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
                child: const Text(
                  'Удалить',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

String _peerLabel({required bool isGroupChat, String? peerName}) {
  final name = peerName?.trim();
  if (isGroupChat) {
    return 'Также удалить у всех участников';
  }
  if (name != null && name.isNotEmpty) {
    return 'Также удалить у $name';
  }
  return 'Также удалить у собеседника';
}
