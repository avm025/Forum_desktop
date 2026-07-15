import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dialogs_list_view_model.dart';
import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/emoticon_replacer.dart';
import 'dialog_tile.dart';
import 'media_thumb_tile.dart';

/// Пересылка сообщения: список чатов (как на главном экране) + композер снизу.
class ForwardDialogPicker extends StatefulWidget {
  final MessageViewModel message;
  final String? excludeDlgId;

  const ForwardDialogPicker({
    super.key,
    required this.message,
    this.excludeDlgId,
  });

  /// Открывает окно пересылки. Возвращает id выбранного чата, если отправлено.
  static Future<String?> show(
    BuildContext context, {
    required MessageViewModel message,
    String? excludeDlgId,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ForwardDialogPicker(
          message: message,
          excludeDlgId: excludeDlgId,
        ),
      ),
    );
  }

  @override
  State<ForwardDialogPicker> createState() => _ForwardDialogPickerState();
}

class _ForwardDialogPickerState extends State<ForwardDialogPicker> {
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  String _query = '';
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  bool _sameDlgId(String? a, String? b) => AppState.sameDlgId(a, b);

  List<DialogsListViewModel> _dialogs(AppState state) {
    final exclude = widget.excludeDlgId?.trim();
    return state.allDialogs.where((d) {
      final id = d.id?.trim();
      if (id == null || id.isEmpty) return false;
      if (exclude != null && exclude.isNotEmpty && _sameDlgId(id, exclude)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<DialogsListViewModel> _filtered(List<DialogsListViewModel> dialogs) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return dialogs;
    return dialogs
        .where((d) => d.chatName.toLowerCase().contains(q))
        .toList();
  }

  void _select(String dlgId) {
    setState(() {
      if (!_selectedIds.remove(dlgId)) _selectedIds.add(dlgId);
    });
    if (_selectedIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocus.requestFocus();
      });
    }
  }

  Future<void> _send() async {
    if (_selectedIds.isEmpty) return;
    final comment = EmoticonReplacer.replace(_commentController.text.trim());

    await context.read<AppState>().forwardMessage(
          widget.message,
          _selectedIds.toList(),
          comment: comment,
        );
    if (mounted) Navigator.of(context).pop(_selectedIds.first);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final dialogs = _filtered(_dialogs(state));

    return Scaffold(
      backgroundColor: p.bg1,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(p),
            _searchField(p),
            const SizedBox(height: 4),
            Expanded(
              child: dialogs.isEmpty
                  ? _emptyState(p)
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: dialogs.length,
                      itemBuilder: (context, index) {
                        final dialog = dialogs[index];
                        final dlgId = dialog.id!.trim();
                        return DialogTile(
                          dialog: dialog,
                          selected: _selectedIds.contains(dlgId),
                          onTap: () => _select(dlgId),
                        );
                      },
                    ),
            ),
            if (_selectedIds.isNotEmpty) _composer(p),
          ],
        ),
      ),
    );
  }

  Widget _header(ForumPalette p) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: p.text1),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Text(
            'Переслать',
            style: TextStyle(
              color: p.text1,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(ForumPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: p.bg2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          cursorColor: p.purple,
          style: TextStyle(color: p.text1, fontSize: 15),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            prefixIcon: Icon(Icons.search, color: p.text2, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 36),
            hintText: 'Поиск чатов',
            hintStyle: TextStyle(color: p.text2, fontSize: 15),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ForumPalette p) {
    return Center(
      child: Text(
        'Чаты не найдены',
        style: TextStyle(color: p.text2, fontSize: 15),
      ),
    );
  }

  Widget _composer(ForumPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.bg1,
        border: Border(top: BorderSide(color: p.border1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ForwardedPreview(message: widget.message),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocus,
                      style: TextStyle(color: p.text1, fontSize: 15),
                      minLines: 1,
                      maxLines: 5,
                      cursorColor: p.purple,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        hintText: 'Добавить комментарий...',
                        hintStyle: TextStyle(color: p.text2, fontSize: 15),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: p.purple,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_selectedIds.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Плашка с пересылаемым сообщением над полем ввода.
class _ForwardedPreview extends StatelessWidget {
  final MessageViewModel message;

  const _ForwardedPreview({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final author = message.my
        ? 'Вы'
        : (message.fr_name.trim().isNotEmpty ? message.fr_name.trim() : 'Сообщение');
    final preview = message.quotedPreviewText;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 36,
            color: p.purple.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Icon(Icons.forward_rounded, size: 16, color: p.purple),
          if (message.quotedShowsMediaThumb) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: MediaThumbTile(
                file: message.quotedFirstFile!,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Переслано от: $author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (preview.isNotEmpty)
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text2, fontSize: 12, height: 1.2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
