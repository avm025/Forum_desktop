import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

/// Экран «Написать сообщение» — выбор контакта (iOS NewMessageViewController).
class NewMessagePicker extends StatefulWidget {
  const NewMessagePicker({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NewMessagePicker(),
      ),
    );
  }

  @override
  State<NewMessagePicker> createState() => _NewMessagePickerState();
}

class _NewMessagePickerState extends State<NewMessagePicker> {
  String _query = '';

  List<DialogsListViewModel> _filtered(List<DialogsListViewModel> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((d) {
          final name = d.chatName.toLowerCase();
          final phone = (d.phone ?? '').toLowerCase();
          final uid = (d.usr_id ?? '').toLowerCase();
          return name.contains(q) || phone.contains(q) || uid.contains(q);
        })
        .toList();
  }

  Map<String, List<DialogsListViewModel>> _sections(
    List<DialogsListViewModel> contacts,
  ) {
    final map = <String, List<DialogsListViewModel>>{};
    for (final c in contacts) {
      final name = c.chatName.trim();
      final letter = name.isNotEmpty ? name[0].toUpperCase() : '#';
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

  Future<void> _open(DialogsListViewModel contact) async {
    final nav = Navigator.of(context);
    await context.read<AppState>().openDialogFromContact(contact);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final contacts = context.watch<AppState>().privateContactsForNewMessage;
    final filtered = _filtered(contacts);
    final sections = _sections(filtered);

    return Scaffold(
      backgroundColor: p.bg1,
      appBar: AppBar(
        backgroundColor: p.bg2,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Отмена',
            style: TextStyle(color: p.purple, fontSize: 15),
          ),
        ),
        leadingWidth: 90,
        title: Text(
          'Написать сообщение',
          style: TextStyle(
            color: p.text1,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
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
                style: TextStyle(color: p.text1, fontSize: 15),
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
          Divider(height: 1, color: p.border1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      contacts.isEmpty
                          ? 'Нет контактов'
                          : 'Ничего не найдено',
                      style: TextStyle(color: p.text2, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    itemCount: sections.length,
                    itemBuilder: (context, sectionIndex) {
                      final letter = sections.keys.elementAt(sectionIndex);
                      final items = sections[letter]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: p.bg2,
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                            child: Text(
                              letter,
                              style: TextStyle(
                                color: p.text1,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (var i = 0; i < items.length; i++)
                            _ContactRow(
                              contact: items[i],
                              showDivider: i < items.length - 1,
                              onTap: () => _open(items[i]),
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
  final bool showDivider;
  final VoidCallback onTap;

  const _ContactRow({
    required this.contact,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isNew = contact.isNewContactWithoutDialog;

    return Material(
      color: p.bg1,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  AvatarWidget(
                    name: contact.chatName,
                    avatarUrl: contact.avatar,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.chatName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isNew)
                          Text(
                            'Написать первое сообщение',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text2,
                              fontSize: 13,
                            ),
                          )
                        else if ((contact.phone ?? '').trim().isNotEmpty)
                          Text(
                            contact.phone!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text2,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(left: 66),
                child: Divider(height: 1, color: p.border1),
              ),
          ],
        ),
      ),
    );
  }
}
