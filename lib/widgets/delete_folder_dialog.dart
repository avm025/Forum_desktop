import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Подтверждение удаления папки.
Future<bool> showDeleteFolderDialog(BuildContext context) {
  final p = context.palette;

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: p.bg2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border1.withValues(alpha: 0.55)),
        ),
        title: Text(
          'Удалить папку?',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Папка будет удалена из списка. Это не затронет чаты, которые в ней находятся.',
          style: TextStyle(color: p.text2, fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Отмена', style: TextStyle(color: p.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      );
    },
  ).then((v) => v ?? false);
}
