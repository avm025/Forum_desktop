import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/forum_api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Экран сортировки папок (drag-and-drop пользовательских папок).
class FolderSortScreen extends StatefulWidget {
  const FolderSortScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FolderSortScreen()),
    );
  }

  @override
  State<FolderSortScreen> createState() => _FolderSortScreenState();
}

class _FolderSortScreenState extends State<FolderSortScreen> {
  late List<({String id, String label, bool canReorder})> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(context.read<AppState>().folderSortItems);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final arr = state.buildFolderSortPayload(_items);

    try {
      await state.sortFolders(arr);
      if (mounted) Navigator.of(context).pop();
    } on ForumApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.bg1,
      appBar: AppBar(
        backgroundColor: p.bg1,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: p.text1),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Изменить порядок',
          style: TextStyle(
            color: p.text1,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.purple,
                    ),
                  )
                : Text(
                    'Готово',
                    style: TextStyle(
                      color: p.purple,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        onReorderItem: (oldIndex, newIndex) {
          if (oldIndex < 3 || newIndex < 3) return;
          setState(() {
            final item = _items.removeAt(oldIndex);
            _items.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final item = _items[index];
          final row = _SortRow(
            key: ValueKey(item.id),
            label: item.label,
            canReorder: item.canReorder,
            index: index,
          );
          if (!item.canReorder) return row;
          return ReorderableDragStartListener(index: index, child: row);
        },
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  final String label;
  final bool canReorder;
  final int index;

  const _SortRow({
    super.key,
    required this.label,
    required this.canReorder,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Material(
      color: p.bg1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          label,
          style: TextStyle(
            color: p.text1,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: canReorder
            ? Icon(Icons.drag_handle_rounded, color: p.text2)
            : null,
      ),
    );
  }
}
