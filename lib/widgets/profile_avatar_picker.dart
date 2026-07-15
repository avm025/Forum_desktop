import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Bottom sheet выбора фото для аватара (упрощённый Telegram-style).
Future<void> showProfileAvatarPicker(BuildContext context) async {
  final state = context.read<AppState>();
  final profile = state.profile;
  final hasPhoto = (profile?.avatarUrl ?? '').trim().isNotEmpty;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final p = sheetContext.palette;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: p.bg2,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Выберите фото',
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    _PickerTile(
                      icon: Icons.photo_library_outlined,
                      label: 'Выбрать из галереи',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _pickFromGallery(context);
                      },
                    ),
                    if (hasPhoto) ...[
                      Divider(height: 1, color: p.border1),
                      _PickerTile(
                        icon: Icons.delete_outline,
                        label: 'Удалить фото',
                        destructive: true,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _removeAvatar(context);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: p.bg2,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: _PickerTile(
                  label: 'Отмена',
                  centered: true,
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _pickFromGallery(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;

  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return;
  if (!context.mounted) return;

  final state = context.read<AppState>();
  final error = await state.updateProfileAvatar(
    bytes: bytes,
    fileName: file.name.isNotEmpty ? file.name : 'avatar.jpg',
  );
  if (!context.mounted) return;

  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error)),
    );
  }
}

Future<void> _removeAvatar(BuildContext context) async {
  final state = context.read<AppState>();
  final error = await state.removeProfileAvatar();
  if (!context.mounted) return;
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error)),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool centered;

  const _PickerTile({
    this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = destructive ? Colors.redAccent : p.text1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: centered
              ? Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: p.purple,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: destructive ? Colors.redAccent : p.purple),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
