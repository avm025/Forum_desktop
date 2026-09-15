import 'dart:async';
import 'dart:io';

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
import '../utils/chat_file_dnd.dart';
import '../utils/cursor_position.dart';
import '../utils/emoticon_replacer.dart';
import '../utils/file_kind.dart';
import '../utils/media_message_layout.dart';
import '../utils/mention_markup.dart';
import '../utils/utf16.dart';
import 'mention_picker.dart';
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
  MessageViewModel? _lastEditTarget;
  String? _boundDlgId;
  int _appliedDraftEpoch = -1;
  bool _syncingText = false;
  bool _pasteBusy = false;

  /// Выбранные `@label` → usr_id для MarkdownV2 при отправке.
  final Map<String, String> _mentionTokens = {};
  MentionQuery? _mentionQuery;
  List<MentionCandidate> _mentionCandidates = const [];
  int _mentionIndex = 0;

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
    // Прикрепляем к полю ввода; текст черновика не трогаем.
    context.read<AppState>().addComposerAttachments([
      MediaFile(
        fname: saved.fileName,
        title: saved.fileName,
        kind: 'jpeg',
        size: saved.size,
        URL: saved.path,
        width: saved.width.isNotEmpty ? saved.width : '248',
        height: saved.height.isNotEmpty ? saved.height : '248',
      ),
    ]);
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

    if (_mentionQuery != null && _mentionCandidates.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _mentionIndex = (_mentionIndex + 1) % _mentionCandidates.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _mentionIndex =
              (_mentionIndex - 1 + _mentionCandidates.length) %
                  _mentionCandidates.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _closeMentionPicker();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _insertMention(_mentionCandidates[
            _mentionIndex.clamp(0, _mentionCandidates.length - 1)]);
        return KeyEventResult.handled;
      }
    }

    // Enter — отправка; Shift+Enter — новая строка + каретка в поле.
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _ensureComposerCaret();
        _insertNewlineAtCaret();
        return KeyEventResult.handled;
      }
      unawaited(_send());
      return KeyEventResult.handled;
    }

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

  void _ensureComposerCaret() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    final sel = _controller.selection;
    if (!sel.isValid) {
      final len = _controller.text.length;
      _controller.selection = TextSelection.collapsed(
        offset: len,
        affinity: TextAffinity.downstream,
      );
    }
  }

  void _insertNewlineAtCaret() {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start;
    final end = selection.end;
    final next = value.text.replaceRange(start, end, '\n');
    final caret = start + 1;
    _syncingText = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: caret,
        affinity: TextAffinity.downstream,
      ),
      composing: TextRange.empty,
    );
    _syncingText = false;
    final has = next.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    context.read<AppState>().reportComposerText(next);
    // Каретка должна мигать в поле после перевода строки.
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
    });
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
    // Прикрепляем; ранее введённый текст остаётся.
    context.read<AppState>().addComposerAttachments([
      MediaFile(
        fname: saved.fileName,
        title: saved.fileName,
        kind: 'jpeg',
        size: saved.size,
        URL: saved.path,
        width: saved.width.isNotEmpty ? saved.width : '248',
        height: saved.height.isNotEmpty ? saved.height : '248',
      ),
    ]);
    return true;
  }

  Future<void> _insertClipboardTextFallback() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty || !mounted) return;
      final safe = sanitizeUtf16(text);
      final value = _controller.value;
      final start = value.selection.start >= 0
          ? value.selection.start
          : value.text.length;
      final end =
          value.selection.end >= 0 ? value.selection.end : value.text.length;
      final newText = value.text.replaceRange(start, end, safe);
      _syncingText = true;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + safe.length),
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
    _syncMentionPicker();
  }

  void _closeMentionPicker() {
    if (_mentionQuery == null && _mentionCandidates.isEmpty) return;
    setState(() {
      _mentionQuery = null;
      _mentionCandidates = const [];
      _mentionIndex = 0;
    });
  }

  void _syncMentionPicker() {
    final state = context.read<AppState>();
    final dialog = state.selectedDialog;
    if (dialog == null || !dialog.isGrp || dialog.awaitingJoin) {
      if (_mentionQuery != null) _closeMentionPicker();
      return;
    }

    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_mentionQuery != null) _closeMentionPicker();
      return;
    }

    final query = MentionQuery.atCaret(_controller.text, sel.baseOffset);
    if (query == null) {
      if (_mentionQuery != null) _closeMentionPicker();
      return;
    }

    final dlgId = dialog.id?.trim() ?? '';
    if (dlgId.isEmpty) return;
    if (state.groupMembers(dlgId).isEmpty) {
      unawaited(state.ensureGroupMembers(dlgId));
    }

    final candidates = state.mentionCandidatesFor(dlgId, query: query.query);
    setState(() {
      _mentionQuery = query;
      _mentionCandidates = candidates;
      if (_mentionIndex >= candidates.length) {
        _mentionIndex = 0;
      }
    });
  }

  void _insertMention(MentionCandidate candidate) {
    final q = _mentionQuery;
    if (q == null) return;
    final text = _controller.text;
    final caret = _controller.selection.isValid
        ? _controller.selection.baseOffset
        : text.length;
    final label = candidate.insertLabel;
    final token = '@$label';
    final insertion = '$token ';
    final next = text.replaceRange(q.atIndex, caret, insertion);
    final newCaret = q.atIndex + insertion.length;

    _mentionTokens[token] = candidate.usrId;

    _syncingText = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    _syncingText = false;
    setState(() {
      _hasText = next.trim().isNotEmpty;
      _mentionQuery = null;
      _mentionCandidates = const [];
      _mentionIndex = 0;
    });
    context.read<AppState>().reportComposerText(next);
    _focusNode.requestFocus();
  }

  String _bodyForSend(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    return MentionMarkup.applyTokens(trimmed, _mentionTokens);
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
        _mentionTokens.clear();
        _syncingText = true;
        _controller.clear();
        _syncingText = false;
        if (_hasText) setState(() => _hasText = false);
        _closeMentionPicker();
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

    final draft = sanitizeUtf16(state.takeComposerDraft(dlgId) ?? '');
    _appliedDraftEpoch = state.composerDraftEpoch;
    if (draft.isEmpty) return;

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
    final state = context.read<AppState>();
    final text = _bodyForSend(EmoticonReplacer.replace(_controller.text));
    final editing = state.editingMessage;
    final hasPending = state.hasComposerPendingAttachments;

    if (editing != null) {
      if (text.isEmpty) return;
      _syncingText = true;
      _controller.clear();
      _syncingText = false;
      _mentionTokens.clear();
      _closeMentionPicker();
      if (_hasText) setState(() => _hasText = false);
      state.reportComposerText('');
      await state.submitEditedMessage(text);
      return;
    }

    if (!hasPending && text.isEmpty) return;

    // Очищаем поле до append скелета — пузырь и текст в одном кадре.
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    _mentionTokens.clear();
    _closeMentionPicker();
    if (_hasText) setState(() => _hasText = false);
    state.reportComposerText('');

    if (hasPending) {
      await state.sendComposerPending(caption: text);
      return;
    }
    await state.sendMessage(text);
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
    context.read<AppState>().addComposerAttachments(files);
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
    context.read<AppState>().addComposerAttachments(files);
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
    context.read<AppState>().addComposerAttachments(files);
  }

  Widget _pendingStrip(AppState state, ForumPalette p) {
    final pending = state.composerPendingAttachments;
    if (pending.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 72,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final file = pending[i];
          return _ComposerPendingThumb(
            file: file,
            onRemove: () => state.removeComposerAttachmentAt(i),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final replyTo = state.replyToMessage;
    final editing = state.editingMessage;

    _scheduleDialogBinding(state);

    if (editing != null && !identical(editing, _lastEditTarget)) {
      _lastEditTarget = editing;
      final seed = editing.body.trim().isNotEmpty
          ? editing.body.trim()
          : (editing.desc.trim().isNotEmpty
              ? editing.desc.trim()
              : editing.text.trim());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncingText = true;
        _controller.value = TextEditingValue(
          text: seed,
          selection: TextSelection.collapsed(offset: seed.length),
        );
        _syncingText = false;
        setState(() => _hasText = seed.trim().isNotEmpty);
        _focusNode.requestFocus();
      });
    } else if (editing == null) {
      _lastEditTarget = null;
    }

    if (replyTo != null && !identical(replyTo, _lastReplyTarget)) {
      _lastReplyTarget = replyTo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (replyTo == null) {
      _lastReplyTarget = null;
    }

    final banner = editing ?? replyTo;
    final hasPending = state.hasComposerPendingAttachments;
    final showSend = _hasText || hasPending || editing != null;

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
            if (banner != null)
              MessageComposerReply(
                message: banner,
                isEdit: editing != null,
                onClose: () {
                  if (editing != null) {
                    state.clearEditMessage();
                  } else {
                    state.clearReplyTo();
                  }
                },
              ),
            _pendingStrip(state, p),
            if (_mentionQuery != null && _mentionCandidates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: MentionPicker(
                  candidates: _mentionCandidates,
                  selectedIndex: _mentionIndex,
                  onHighlight: (i) => setState(() => _mentionIndex = i),
                  onSelect: _insertMention,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: editing != null ? null : _openAttachMenu,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.attach_file,
                        color: editing != null
                            ? p.text2.withValues(alpha: 0.4)
                            : p.text2,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        inputFormatters: const [Utf16SanitizingFormatter()],
                        style: TextStyle(color: p.text1, fontSize: 15),
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        showCursor: true,
                        cursorWidth: 2,
                        cursorColor: p.purple,
                        enableInteractiveSelection: true,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          hintText: editing != null
                              ? 'Изменить...'
                              : (replyTo == null ? 'Сообщение...' : 'Ответ...'),
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
                        showSend ? Icons.send_rounded : Icons.mic,
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

class _ComposerPendingThumb extends StatelessWidget {
  final MediaFile file;
  final VoidCallback onRemove;

  const _ComposerPendingThumb({
    required this.file,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isMedia = ChatFileDnd.isMediaAttachment(file);

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: p.bg3,
                child: isMedia ? _mediaPreview() : _filePreview(p),
              ),
            ),
          ),
          if (file.isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 22),
            ),
          Positioned(
            top: -4,
            right: -4,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: p.bg2,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.border1),
                  ),
                  child: Icon(Icons.close, size: 12, color: p.text1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaPreview() {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    final path = file.URL?.trim() ?? '';
    if (path.isNotEmpty) {
      try {
        final local = path.startsWith('file://')
            ? Uri.parse(path).toFilePath()
            : path;
        final f = File(local);
        if (f.existsSync()) {
          return Image.file(f, fit: BoxFit.cover, gaplessPlayback: true);
        }
      } catch (_) {}
    }
    return const Center(
      child: Icon(Icons.image_outlined, color: Colors.white54, size: 22),
    );
  }

  Widget _filePreview(ForumPalette p) {
    final name = (file.title.isNotEmpty ? file.title : file.fname).trim();
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: p.purple, size: 20),
          const SizedBox(height: 2),
          Text(
            name.isEmpty ? 'файл' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text2, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
