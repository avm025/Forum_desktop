import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/forum_api_client.dart';
import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/global_search.dart';
import '../utils/utf16.dart';
import 'avatar_widget.dart';
import 'folder_name_dialog.dart';

/// Создание группы: выбор контактов → название → WS `dlg` (dlg.md).
class CreateGroupPicker extends StatefulWidget {
  const CreateGroupPicker({super.key});

  static Future<void> open(BuildContext context) async {
    final userIds = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CreateGroupPicker(),
      ),
    );
    if (userIds == null || !context.mounted) return;

    final name = await showFolderNameDialog(
      context,
      title: 'Введите название группы',
      confirmLabel: 'Создать',
    );
    if (name == null || !context.mounted) return;

    try {
      await context.read<AppState>().createGroup(
            name: name,
            userIds: userIds,
          );
    } on ForumApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать группу: $e')),
        );
      }
    }
  }

  @override
  State<CreateGroupPicker> createState() => _CreateGroupPickerState();
}

class _CreateGroupPickerState extends State<CreateGroupPicker> {
  final Set<String> _selectedUserIds = {};
  String _query = '';

  List<DialogsListViewModel> _filtered(List<DialogsListViewModel> all) {
    final q = _query.trim();
    if (q.isEmpty) return all;
    return all.where((d) => GlobalSearch.dialogMatchesQuery(d, q)).toList();
  }

  Map<String, List<DialogsListViewModel>> _sections(
    List<DialogsListViewModel> contacts,
  ) {
    final map = <String, List<DialogsListViewModel>>{};
    for (final c in contacts) {
      final letter = sectionLetterForName(c.chatName);
      map.putIfAbsent(letter, () => <DialogsListViewModel>[]).add(c);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return {for (final k in keys) k: map[k]!};
  }

  void _toggle(DialogsListViewModel contact) {
    final uid = contact.usr_id?.trim() ?? '';
    if (uid.isEmpty) return;
    setState(() {
      if (!_selectedUserIds.remove(uid)) _selectedUserIds.add(uid);
    });
  }

  void _continue() => Navigator.of(context).pop(_selectedUserIds.toList());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final contacts = context.watch<AppState>().privateContactsForNewMessage;
    final filtered = _filtered(contacts);
    final sections = _sections(filtered);
    final selectedCount = _selectedUserIds.length;

    return Scaffold(
      backgroundColor: p.bg1,
      appBar: AppBar(
        backgroundColor: p.bg2,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: p.text1, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Группа',
          style: TextStyle(
            color: p.text1,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _continue,
            child: Text(
              selectedCount == 0 ? 'Далее' : 'Далее ($selectedCount)',
              style: TextStyle(
                color: p.purple,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: p.bg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                inputFormatters: const [Utf16SanitizingFormatter()],
                style: TextStyle(color: p.text1, fontSize: 15),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  prefixIcon: Icon(Icons.search, color: p.text2, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 36),
                  hintText: 'Кого добавить в группу?',
                  hintStyle: TextStyle(color: p.text2, fontSize: 15),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Выбрано: $selectedCount',
                  style: TextStyle(color: p.text2, fontSize: 13),
                ),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Контакты не найдены',
                      style: TextStyle(color: p.text2, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    itemCount: sections.length,
                    itemBuilder: (context, sectionIndex) {
                      final letter = sections.keys.elementAt(sectionIndex);
                      final list = sections[letter]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              letter,
                              style: TextStyle(
                                color: p.purple,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final contact in list)
                            _ContactRow(
                              contact: contact,
                              selected: _selectedUserIds
                                  .contains(contact.usr_id?.trim() ?? ''),
                              onTap: () => _toggle(contact),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final DialogsListViewModel contact;
  final bool selected;
  final VoidCallback onTap;

  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            AvatarWidget(
              name: contact.chatName,
              avatarUrl: contact.avatar,
              avatarColor: contact.avatarColor,
              colAvaId: contact.colAvaId,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                contact.chatName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.text1,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? p.purple : Colors.transparent,
                border: Border.all(
                  color: selected ? p.purple : p.border2,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
