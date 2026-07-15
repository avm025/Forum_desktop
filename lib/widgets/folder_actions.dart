import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/forum_api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'delete_folder_dialog.dart';
import 'folder_chat_picker.dart';
import 'folder_name_dialog.dart';
import 'folder_sort_screen.dart';

/// Контекстное меню вкладки папки.
class FolderActions {
  FolderActions._();

  static Future<void> showTabMenu(
    BuildContext context, {
    required String tabId,
    required String label,
  }) async {
    final state = context.read<AppState>();
    final isUser = state.isUserFolderTab(tabId);
    final p = context.palette;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUser) ...[
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: p.purple),
                  title:
                      Text('Изменить имя', style: TextStyle(color: p.text1)),
                  onTap: () => Navigator.pop(sheetContext, 'rename'),
                ),
                ListTile(
                  leading:
                      Icon(Icons.person_add_alt_1_outlined, color: p.purple),
                  title:
                      Text('Добавить чаты', style: TextStyle(color: p.text1)),
                  onTap: () => Navigator.pop(sheetContext, 'chats'),
                ),
              ],
              ListTile(
                leading: Icon(Icons.swap_vert_rounded, color: p.purple),
                title:
                    Text('Изменить порядок', style: TextStyle(color: p.text1)),
                onTap: () => Navigator.pop(sheetContext, 'sort'),
              ),
              if (isUser)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text(
                    'Удалить',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case 'rename':
        await _rename(context, tabId, label);
      case 'chats':
        await _editChats(context, tabId);
      case 'sort':
        await FolderSortScreen.open(context);
      case 'delete':
        await _delete(context, tabId);
    }
  }

  static Future<void> _rename(
    BuildContext context,
    String tabId,
    String currentName,
  ) async {
    final name = await showFolderNameDialog(
      context,
      title: 'Изменить имя',
      initialName: currentName,
    );
    if (name == null || !context.mounted) return;

    try {
      await context.read<AppState>().renameFolder(id: tabId, name: name);
    } on ForumApiException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  static Future<void> _editChats(BuildContext context, String tabId) async {
    final group = context.read<AppState>().groupById(tabId);
    if (group == null) return;

    await FolderChatPicker.openEdit(
      context,
      folderId: tabId,
      initialSelected: group.dialogIds,
    );
  }

  static Future<void> _delete(BuildContext context, String tabId) async {
    final confirmed = await showDeleteFolderDialog(context);
    if (!confirmed || !context.mounted) return;

    try {
      await context.read<AppState>().deleteFolder(tabId);
    } on ForumApiException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
