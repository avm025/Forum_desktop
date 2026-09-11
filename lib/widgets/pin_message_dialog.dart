import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Результат диалога закрепления / открепления.
class PinMessageResult {
  /// `true` — закрепить/открепить и у собеседника (как Telegram «у меня и …»).
  final bool forBoth;

  const PinMessageResult({required this.forBoth});
}

/// Подтверждение закрепления в стиле Telegram.
Future<PinMessageResult?> showPinMessageDialog({
  required BuildContext context,
  required bool isGroupChat,
  String? peerName,
}) {
  return _showPinDialog(
    context: context,
    title: 'Хотите закрепить это сообщение?',
    confirmLabel: 'Закрепить',
    isGroupChat: isGroupChat,
    peerName: peerName,
    bothLabelBuilder: _pinBothLabel,
  );
}

/// Подтверждение открепления в стиле Telegram.
Future<PinMessageResult?> showUnpinMessageDialog({
  required BuildContext context,
  required bool isGroupChat,
  String? peerName,
}) {
  return _showPinDialog(
    context: context,
    title: 'Хотите открепить это сообщение?',
    confirmLabel: 'Открепить',
    isGroupChat: isGroupChat,
    peerName: peerName,
    bothLabelBuilder: _unpinBothLabel,
  );
}

Future<PinMessageResult?> _showPinDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required bool isGroupChat,
  required String? peerName,
  required String Function({required bool isGroupChat, String? peerName})
      bothLabelBuilder,
}) {
  final p = context.palette;
  var forBoth = false;

  return showDialog<PinMessageResult>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: p.bg2,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.border1.withValues(alpha: 0.55)),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.text1,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => forBoth = !forBoth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: forBoth,
                        onChanged: (value) =>
                            setState(() => forBoth = value ?? false),
                        activeColor: p.purple,
                        side: BorderSide(color: p.text3),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          bothLabelBuilder(
                            isGroupChat: isGroupChat,
                            peerName: peerName,
                          ),
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
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        backgroundColor: p.bg3,
                        foregroundColor: p.text1,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Отмена', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        PinMessageResult(forBoth: forBoth),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: p.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

String _pinBothLabel({required bool isGroupChat, String? peerName}) {
  if (isGroupChat) {
    return 'Закрепить у всех участников';
  }
  final name = peerName?.trim();
  if (name != null && name.isNotEmpty) {
    return 'Закрепить у меня и $name';
  }
  return 'Закрепить у меня и собеседника';
}

String _unpinBothLabel({required bool isGroupChat, String? peerName}) {
  if (isGroupChat) {
    return 'Также открепить у всех участников';
  }
  final name = peerName?.trim();
  if (name != null && name.isNotEmpty) {
    return 'Также открепить у $name';
  }
  return 'Также открепить у собеседника';
}
