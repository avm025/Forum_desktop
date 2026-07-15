import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_file.dart';
import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/emoticon_replacer.dart';
import '../utils/file_kind.dart';
import '../utils/media_message_layout.dart';
import 'message_composer_reply.dart';

/// Поле ввода сообщения: скрепка, текст, кнопка отправки/микрофон.
class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  MessageViewModel? _lastReplyTarget;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = EmoticonReplacer.replace(_controller.text.trim());
    if (text.isEmpty) return;
    await context.read<AppState>().sendMessage(text);
    if (mounted) _controller.clear();
  }

  Future<void> _openAttachMenu() async {
    final p = context.palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_outlined, color: p.purple),
                title: Text('Фото', style: TextStyle(color: p.text1)),
                onTap: () => Navigator.pop(context, 'photo'),
              ),
              ListTile(
                leading: Icon(Icons.videocam_outlined, color: p.purple),
                title: Text('Видео', style: TextStyle(color: p.text1)),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: Icon(Icons.insert_drive_file_outlined,
                    color: p.purple),
                title: Text('Файл', style: TextStyle(color: p.text1)),
                onTap: () => Navigator.pop(context, 'file'),
              ),
            ],
          ),
        );
      },
    );

    if (choice == 'photo') {
      await _pickPhotos();
    } else if (choice == 'video') {
      await _pickVideos();
    } else if (choice == 'file') {
      await _pickFile();
    }
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .take(MediaMessageLayout.maxFiles)
        .map((f) => MediaFile(
              fname: f.name,
              kind: FileKind.kindFromName(f.name),
              size: f.size,
              width: '248',
              height: '248',
              bytes: f.bytes,
              URL: f.path,
            ))
        .toList();

    if (!mounted) return;
    context.read<AppState>().sendMediaMessage(
          files,
          caption: _controller.text,
        );
    _controller.clear();
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .take(MediaMessageLayout.maxFiles)
        .map((f) => MediaFile(
              fname: f.name,
              kind: FileKind.kindFromName(f.name),
              size: f.size,
              bytes: f.bytes,
              URL: f.path,
            ))
        .toList();

    if (!mounted) return;
    context.read<AppState>().sendMediaMessage(
          files,
          caption: _controller.text,
        );
    _controller.clear();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .take(MediaMessageLayout.maxFiles)
        .map((f) => MediaFile(
              fname: f.name,
              kind: FileKind.kindFromName(f.name),
              size: f.size,
              title: f.name,
              bytes: f.bytes,
              URL: f.path,
            ))
        .toList();

    if (!mounted) return;
    context.read<AppState>().sendFileMessage(files);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final replyTo = state.replyToMessage;

    if (replyTo != null && !identical(replyTo, _lastReplyTarget)) {
      _lastReplyTarget = replyTo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (replyTo == null) {
      _lastReplyTarget = null;
    }

    return Container(
      decoration: BoxDecoration(
        color: p.bg1,
        border: Border(top: BorderSide(color: p.border1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null)
            MessageComposerReply(
              message: replyTo,
              onClose: state.clearReplyTo,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                InkWell(
                  onTap: _openAttachMenu,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.attach_file, color: p.text2, size: 24),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: TextStyle(color: p.text1, fontSize: 15),
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: replyTo == null ? 'Сообщение...' : 'Ответ...',
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: p.purple,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _hasText ? Icons.send_rounded : Icons.mic,
                      color: Colors.white,
                      size: 20,
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
