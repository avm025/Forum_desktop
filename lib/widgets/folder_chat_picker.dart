import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/forum_api_client.dart';
import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'dialog_tile.dart';
import 'folder_name_dialog.dart';

/// Выбор чатов для папки (создание или редактирование состава).
class FolderChatPicker extends StatefulWidget {
  final String title;
  final Set<String> initialSelected;
  final bool showNameStep;

  const FolderChatPicker({
    super.key,
    required this.title,
    this.initialSelected = const {},
    this.showNameStep = false,
  });

  /// Создание папки: выбор чатов → ввод названия.
  static Future<void> openCreate(BuildContext context) async {
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const FolderChatPicker(
          title: 'Выберите чаты',
          showNameStep: true,
        ),
      ),
    );
    if (ids == null || !context.mounted) return;

    final name = await showFolderNameDialog(
      context,
      title: 'Название папки',
      confirmLabel: 'Создать',
    );
    if (name == null || !context.mounted) return;

    try {
      await context.read<AppState>().createFolder(
            name: name,
            dialogIds: ids,
          );
    } on ForumApiException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  /// Редактирование состава папки.
  static Future<void> openEdit(
    BuildContext context, {
    required String folderId,
    required Set<String> initialSelected,
  }) async {
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => FolderChatPicker(
          title: 'Добавить чаты',
          initialSelected: initialSelected,
        ),
      ),
    );
    if (ids == null || !context.mounted) return;

    try {
      await context.read<AppState>().updateFolderDialogs(
            id: folderId,
            dialogIds: ids,
          );
    } on ForumApiException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  State<FolderChatPicker> createState() => _FolderChatPickerState();
}

class _FolderChatPickerState extends State<FolderChatPicker> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
  }

  List<DialogsListViewModel> _filtered(AppState state) {
    final q = _query.trim().toLowerCase();
    final dialogs = state.allDialogs;
    if (q.isEmpty) return dialogs;
    return dialogs
        .where((d) => d.chatName.toLowerCase().contains(q))
        .toList();
  }

  void _toggle(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return;
    final id = dlgId.trim();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _done() => Navigator.of(context).pop(_selected.toList());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final dialogs = _filtered(state);

    return Scaffold(
      backgroundColor: p.bg1,
      appBar: AppBar(
        backgroundColor: p.bg1,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: p.text1),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: p.text1,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _done,
            child: Text(
              widget.showNameStep ? 'Далее' : 'Готово',
              style: TextStyle(
                color: p.purple,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: p.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(color: p.text1, fontSize: 15),
                cursorColor: p.purple,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  prefixIcon: Icon(Icons.search, color: p.text2, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 36),
                  hintText: 'Поиск',
                  hintStyle: TextStyle(color: p.text2, fontSize: 15),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: dialogs.isEmpty
                ? Center(
                    child: Text(
                      'Чаты не найдены',
                      style: TextStyle(color: p.text2, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    itemCount: dialogs.length,
                    itemBuilder: (context, index) {
                      final dialog = dialogs[index];
                      final id = dialog.id?.trim() ?? '';
                      return DialogTile(
                        dialog: dialog,
                        selected: _selected.contains(id),
                        onTap: () => _toggle(dialog.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
