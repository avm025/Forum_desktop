import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/media_file.dart';
import '../models/message_view_model.dart';
import '../services/api_logger.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/cursor_position.dart';
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
  String? _boundDlgId;
  int _appliedDraftEpoch = -1;
  bool _syncingText = false;
  bool _pasteBusy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.onKeyEvent = _onKeyEvent;
    CursorPosition.onClipboardImage = _onNativeClipboardImage;
    // Пока композер в дереве — глотаем Cmd+V с картинкой (не только при focus).
    unawaited(CursorPosition.setImagePasteIntercept(true));
  }

  void _onNativeClipboardImage(ClipboardImageFile saved) {
    ApiLogger.instance.logEvent(
      'PASTE',
      'composer got native image ${saved.fileName}',
    );
    if (!mounted) return;
    final caption = _controller.text;
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    if (_hasText) setState(() => _hasText = false);
    context.read<AppState>().reportComposerText('');
    unawaited(
      context.read<AppState>().sendMediaMessage(
        [
          MediaFile(
            fname: saved.fileName,
            title: saved.fileName,
            kind: 'jpeg',
            size: saved.size,
            URL: saved.path,
            width: saved.width.isNotEmpty ? saved.width : '248',
            height: saved.height.isNotEmpty ? saved.height : '248',
          ),
        ],
        caption: caption,
      ),
    );
  }

  @override
  void dispose() {
    if (identical(CursorPosition.onClipboardImage, _onNativeClipboardImage)) {
      CursorPosition.onClipboardImage = null;
    }
    unawaited(CursorPosition.setImagePasteIntercept(false));
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isPaste = (event.logicalKey == LogicalKeyboardKey.keyV) &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (!isPaste) return KeyEventResult.ignored;

    // Перехватываем всегда: системный paste картинки в TextField на macOS
    // подвешивает engine. Текст вставим сами, если картинки нет.
    if (_pasteBusy) return KeyEventResult.handled;
    unawaited(_handlePasteKey());
    return KeyEventResult.handled;
  }

  Future<void> _handlePasteKey() async {
    if (_pasteBusy) return;
    _pasteBusy = true;
    try {
      ApiLogger.instance.logEvent('PASTE', 'cmd+v');
      final sent = await _sendClipboardImageNative();
      if (sent) return;
      ApiLogger.instance.logEvent('PASTE', 'no image → text');
      await _insertClipboardTextFallback();
    } catch (e) {
      ApiLogger.instance.logEvent('PASTE', 'error: $e');
      await _insertClipboardTextFallback();
    } finally {
      _pasteBusy = false;
    }
  }

  /// Native macOS: pasteboard → JPEG temp → send. Без TIFF в Dart heap.
  Future<bool> _sendClipboardImageNative() async {
    if (!CursorPosition.isSupported) return false;

    final hasImage = await CursorPosition.hasClipboardImage();
    ApiLogger.instance.logEvent('PASTE', 'hasClipboardImage=$hasImage');
    if (!hasImage) return false;

    // Дать UI кадр до чтения pasteboard на main (Swift).
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final saved = await CursorPosition.saveClipboardImage();
    if (saved == null) {
      ApiLogger.instance.logEvent('PASTE', 'saveClipboardImage=null');
      return false;
    }
    ApiLogger.instance.logEvent(
      'PASTE',
      'saved ${saved.fileName} ${saved.width}x${saved.height} '
      '${saved.size}b path=${saved.path}',
    );

    if (!mounted) return true;
    final caption = _controller.text;
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    setState(() => _hasText = false);
    context.read<AppState>().reportComposerText('');

    // Не await upload — UI свободен; ошибки в логе MEDIA/UPLOAD.
    unawaited(
      context.read<AppState>().sendMediaMessage(
        [
          MediaFile(
            fname: saved.fileName,
            title: saved.fileName,
            kind: 'jpeg',
            size: saved.size,
            URL: saved.path,
            width: saved.width.isNotEmpty ? saved.width : '248',
            height: saved.height.isNotEmpty ? saved.height : '248',
          ),
        ],
        caption: caption,
      ),
    );
    return true;
  }

  Future<void> _insertClipboardTextFallback() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty || !mounted) return;
      final value = _controller.value;
      final start = value.selection.start >= 0
          ? value.selection.start
          : value.text.length;
      final end =
          value.selection.end >= 0 ? value.selection.end : value.text.length;
      final newText = value.text.replaceRange(start, end, text);
      _syncingText = true;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
      _syncingText = false;
      setState(() => _hasText = newText.trim().isNotEmpty);
      context.read<AppState>().reportComposerText(newText);
    } catch (_) {}
  }

  void _onTextChanged() {
    if (_syncingText) return;
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    context.read<AppState>().reportComposerText(_controller.text);
  }

  void _scheduleDialogBinding(AppState state) {
    final dlgId = state.selectedDialog?.id;
    final epoch = state.composerDraftEpoch;
    if (dlgId == _boundDlgId && epoch == _appliedDraftEpoch) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<AppState>();
      final id = s.selectedDialog?.id;
      if (id != _boundDlgId) {
        _boundDlgId = id;
        _appliedDraftEpoch = -1;
        _syncingText = true;
        _controller.clear();
        _syncingText = false;
        if (_hasText) setState(() => _hasText = false);
      }
      _tryApplyDraft(s, id);
    });
  }

  void _tryApplyDraft(AppState state, String? dlgId) {
    if (dlgId == null || dlgId.isEmpty) return;
    if (state.composerDraftEpoch == _appliedDraftEpoch) return;
    if (_controller.text.trim().isNotEmpty) {
      _appliedDraftEpoch = state.composerDraftEpoch;
      return;
    }

    final draft = state.takeComposerDraft(dlgId);
    _appliedDraftEpoch = state.composerDraftEpoch;
    if (draft == null || draft.isEmpty) return;

    _syncingText = true;
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _syncingText = false;
    setState(() => _hasText = draft.trim().isNotEmpty);
    state.reportComposerText(draft);
  }

  Future<void> _send() async {
    final text = EmoticonReplacer.replace(_controller.text.trim());
    if (text.isEmpty) return;

    // Очищаем поле до append скелета — пузырь и текст в одном кадре.
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    if (_hasText) setState(() => _hasText = false);
    context.read<AppState>().reportComposerText('');

    await context.read<AppState>().sendMessage(text);
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
    // withData: false — скрины Retina не грузим целиком в RAM на UI-isolate.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
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
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    setState(() => _hasText = false);
    context.read<AppState>().reportComposerText('');
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
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    setState(() => _hasText = false);
    context.read<AppState>().reportComposerText('');
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

    _scheduleDialogBinding(state);

    if (replyTo != null && !identical(replyTo, _lastReplyTarget)) {
      _lastReplyTarget = replyTo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (replyTo == null) {
      _lastReplyTarget = null;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => AttachmentSelection.clearIfOutside(),
      child: Container(
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
                        // Не включаем contentInsertionConfiguration с image/*:
                        // иначе Flutter тащит TIFF скрина в Dart и UI виснет.
                        // Картинки: native NSEvent Cmd+V → JPEG temp.
                        decoration: InputDecoration(
                          isCollapsed: true,
                          hintText:
                              replyTo == null ? 'Сообщение...' : 'Ответ...',
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
      ),
    );
  }
}
