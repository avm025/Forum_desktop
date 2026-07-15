import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Диалог ввода названия папки (макс. 24 символа).
Future<String?> showFolderNameDialog(
  BuildContext context, {
  String title = 'Название папки',
  String? initialName,
  String confirmLabel = 'Сохранить',
}) {
  final p = context.palette;
  final controller = TextEditingController(text: initialName ?? '');

  return showDialog<String>(
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
          title,
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: BuiltinTab.maxFolderNameLength,
          style: TextStyle(color: p.text1, fontSize: 15),
          cursorColor: p.purple,
          decoration: InputDecoration(
            hintText: 'Название',
            hintStyle: TextStyle(color: p.text2),
            counterStyle: TextStyle(color: p.text2, fontSize: 12),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.border1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.purple),
            ),
          ),
          onSubmitted: (v) {
            final trimmed = v.trim();
            if (trimmed.isNotEmpty) {
              Navigator.of(dialogContext).pop(trimmed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Отмена', style: TextStyle(color: p.text2)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(dialogContext).pop(trimmed);
            },
            child: Text(confirmLabel, style: TextStyle(color: p.purple)),
          ),
        ],
      );
    },
  );
}
