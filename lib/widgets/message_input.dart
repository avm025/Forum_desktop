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
  /// Отдельно от setState — смена иконки send/mic не трогает TextField.
  final ValueNotifier<bool> _hasText = ValueNotifier(false);
  /// Пикер `@` вне setState композера — закрытие не пересобирает TextField.
  final ValueNotifier<_MentionStrip?> _mentionStrip =
      ValueNotifier<_MentionStrip?>(null);

  MessageViewModel? _lastReplyTarget;
  MessageViewModel? _lastEditTarget;
  String? _boundDlgId;
  int _appliedDraftEpoch = -1;
  bool _syncingText = false;
  bool _pasteBusy = false;

  /// Выбранные `@label` → usr_id для MarkdownV2 при отправке.
  final Map<String, String> _mentionTokens = {};
  String? _lastReportedText;
  bool _mentionSyncScheduled = false;
  bool _membersFetchQueued = false;

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
    _hasText.dispose();
    _mentionStrip.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final strip = _mentionStrip.value;
    if (strip != null && strip.candidates.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _mentionStrip.value = strip.copyWith(
          index: (strip.index + 1) % strip.candidates.length,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _mentionStrip.value = strip.copyWith(
          index: (strip.index - 1 + strip.candidates.length) %
              strip.candidates.length,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _closeMentionPicker();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _insertMention(strip.candidates[
            strip.index.clamp(0, strip.candidates.length - 1)]);
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
    _lastReportedText = next;
    final has = next.trim().isNotEmpty;
    if (has != _hasText.value) _hasText.value = has;
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
      _lastReportedText = newText;
      _hasText.value = newText.trim().isNotEmpty;
      context.read<AppState>().reportComposerText(newText);
    } catch (_) {}
  }

  void _onTextChanged() {
    if (_syncingText) return;
    final text = _controller.text;
    final textChanged = text != _lastReportedText;
    if (textChanged) {
      _lastReportedText = text;
      final has = text.trim().isNotEmpty;
      if (has != _hasText.value) _hasText.value = has;
      context.read<AppState>().reportComposerText(text);
    }
    // Пикер через ValueNotifier — без setState на TextField.
    _scheduleMentionPickerSync();
  }

  void _closeMentionPicker() {
    if (_mentionStrip.value == null) return;
    _mentionStrip.value = null;
  }

  void _scheduleMentionPickerSync() {
    if (_mentionSyncScheduled) return;
    _mentionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mentionSyncScheduled = false;
      if (!mounted) return;
      _syncMentionPicker();
    });
  }

  bool _sameCandidates(
    List<MentionCandidate> a,
    List<MentionCandidate> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].usrId != b[i].usrId || a[i].title != b[i].title) {
        return false;
      }
    }
    return true;
  }

  void _syncMentionPicker() {
    final state = context.read<AppState>();
    final dialog = state.selectedDialog;
    final current = _mentionStrip.value;
    if (dialog == null || !dialog.isGrp || dialog.awaitingJoin) {
      _closeMentionPicker();
      return;
    }

    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _closeMentionPicker();
      return;
    }

    final query = MentionQuery.atCaret(_controller.text, sel.baseOffset);
    if (query == null) {
      _closeMentionPicker();
      return;
    }

    final dlgId = dialog.id?.trim() ?? '';
    if (dlgId.isEmpty) return;

    // Один запрос dlg_info на сессию ввода `@`, без лавины unawaited.
    if (state.groupMembers(dlgId).isEmpty &&
        !state.isGroupMembersLoading(dlgId) &&
        !_membersFetchQueued) {
      _membersFetchQueued = true;
      unawaited(state.ensureGroupMembers(dlgId).whenComplete(() {
        _membersFetchQueued = false;
        if (!mounted) return;
        _scheduleMentionPickerSync();
      }));
    }

    final candidates = state.mentionCandidatesFor(dlgId, query: query.query);
    final sameQuery = current?.query.atIndex == query.atIndex &&
        current?.query.query == query.query;
    if (sameQuery &&
        current != null &&
        _sameCandidates(current.candidates, candidates) &&
        (current.index < candidates.length || candidates.isEmpty)) {
      return;
    }

    var index = current?.index ?? 0;
    if (index >= candidates.length) index = 0;
    _mentionStrip.value = _MentionStrip(
      query: query,
      candidates: candidates,
      index: index,
    );
  }

  void _insertMention(MentionCandidate candidate) {
    final q = _mentionStrip.value?.query;
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
    _lastReportedText = next;
    _hasText.value = next.trim().isNotEmpty;
    _closeMentionPicker();
    context.read<AppState>().reportComposerText(next);
    _focusNode.requestFocus();
  }

  String _bodyForSend(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    return MentionMarkup.applyTokens(trimmed, _mentionTokens);
  }

  void _scheduleDialogBinding(
    AppState state, {
    required String? selectedId,
    required int draftEpoch,
  }) {
    final dlgId = selectedId ?? state.selectedDialog?.id;
    final epoch = draftEpoch;
    if (dlgId == _boundDlgId && epoch == _appliedDraftEpoch) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<AppState>();
      final id = s.selectedDialog?.id;
      if (id != _boundDlgId) {
        _boundDlgId = id;
        _appliedDraftEpoch = -1;
        _mentionTokens.clear();
        _membersFetchQueued = false;
        _lastReportedText = '';
        _syncingText = true;
        _controller.clear();
        _syncingText = false;
        if (_hasText.value) _hasText.value = false;
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
    _lastReportedText = draft;
    _hasText.value = draft.trim().isNotEmpty;
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
      _lastReportedText = '';
      _mentionTokens.clear();
      _closeMentionPicker();
      if (_hasText.value) _hasText.value = false;
      state.reportComposerText('');
      await state.submitEditedMessage(text);
      return;
    }

    if (!hasPending && text.isEmpty) return;

    // Очищаем поле до append скелета — пузырь и текст в одном кадре.
    _syncingText = true;
    _controller.clear();
    _syncingText = false;
    _lastReportedText = '';
    _mentionTokens.clear();
    _closeMentionPicker();
    if (_hasText.value) _hasText.value = false;
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
    // select вместо watch: очистка черновика / typing не пересобирает TextField
    // (иначе после удаления `@` курсор на секунды не ставится ЛКМ).
    final replyTo = context.select((AppState s) => s.replyToMessage);
    final editing = context.select((AppState s) => s.editingMessage);
    final hasPending =
        context.select((AppState s) => s.hasComposerPendingAttachments);
    final draftEpoch = context.select((AppState s) => s.composerDraftEpoch);
    final selectedId = context.select((AppState s) => s.selectedId);
    final p = context.palette;
    final state = context.read<AppState>();

    _scheduleDialogBinding(state, selectedId: selectedId, draftEpoch: draftEpoch);

    if (editing != null && !identical(editing, _lastEditTarget)) {
      _lastEditTarget = editing;
      final seedRaw = editing.body.trim().isNotEmpty
          ? editing.body.trim()
          : (editing.desc.trim().isNotEmpty
              ? editing.desc.trim()
              : editing.text.trim());
      final seed = state.mentionDisplayText(seedRaw);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncingText = true;
        _controller.value = TextEditingValue(
          text: seed,
          selection: TextSelection.collapsed(offset: seed.length),
        );
        _syncingText = false;
        _lastReportedText = seed;
        _hasText.value = seed.trim().isNotEmpty;
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
            // Пикер — сосед TextField (не Stack/Positioned): иначе клики и hover
            // не попадают в список, и «выбранный» ряд не обновляется.
            ValueListenableBuilder<_MentionStrip?>(
              valueListenable: _mentionStrip,
              builder: (context, strip, _) {
                if (strip == null || strip.candidates.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: MentionPicker(
                    candidates: strip.candidates,
                    selectedIndex: strip.index,
                    onHighlight: (i) {
                      final cur = _mentionStrip.value;
                      if (cur == null || i == cur.index) return;
                      _mentionStrip.value = cur.copyWith(index: i);
                    },
                    onSelect: _insertMention,
                  ),
                );
              },
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
                              : (replyTo == null
                                  ? 'Сообщение...'
                                  : 'Ответ...'),
                          hintStyle:
                              TextStyle(color: p.text2, fontSize: 15),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: _hasText,
                    builder: (context, hasText, _) {
                      final showSend =
                          hasText || hasPending || editing != null;
                      return GestureDetector(
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
                      );
                    },
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

/// Состояние полосы `@`-упоминаний вне setState композера.
class _MentionStrip {
  final MentionQuery query;
  final List<MentionCandidate> candidates;
  final int index;

  const _MentionStrip({
    required this.query,
    required this.candidates,
    required this.index,
  });

  _MentionStrip copyWith({
    MentionQuery? query,
    List<MentionCandidate>? candidates,
    int? index,
  }) {
    return _MentionStrip(
      query: query ?? this.query,
      candidates: candidates ?? this.candidates,
      index: index ?? this.index,
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
