import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

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
import '../utils/voice_histogram.dart';
import 'attach_composer_sheet.dart';
import 'mention_picker.dart';
import 'message_composer_reply.dart';
import 'telegram_emoji_overlay.dart';
import 'video_note_recorder.dart';

/// Поле ввода сообщения: скрепка, текст, кнопка отправки/микрофон.
class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with TelegramEmojiOverlayHost {
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

  bool _recording = false;
  bool _recordBusy = false;
  DateTime? _recordStartedAt;
  Timer? _recordTick;
  int _recordElapsed = 0;
  final List<int> _recordLevels = [];
  StreamSubscription<Amplitude>? _ampSub;
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordPath;

  /// Как в Telegram: одна кнопка справа — send ↔ mic ↔ video.
  /// `true` = видеосообщение, `false` = голосовое (пока поле пустое).
  bool _recordVideoMode = false;
  final GlobalKey _recordBtnKey = GlobalKey();
  OverlayEntry? _recordTipOverlay;
  Timer? _recordTipTimer;
  final ValueNotifier<String> _recordTipText = ValueNotifier<String>('');
  double _recordTipLeft = 0;
  double _recordTipTop = 0;
  double _recordTipArrowX = 0;

  /// +20% к иконкам смайла / видео / голоса.
  static const _emojiIconSize = 26.4; // 22 * 1.2
  static const _iconLg = 24.0; // 20 * 1.2
  static const _actionSize = 48.0; // 40 * 1.2
  /// Небольшой зазор после placeholder «Сообщение...».
  static const _hintGap = 12.0;

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
    disposeEmojiOverlay();
    _hideRecordTip();
    _recordTipText.dispose();
    _recordTick?.cancel();
    unawaited(_ampSub?.cancel());
    unawaited(_recorder.dispose());
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _hasText.dispose();
    _mentionStrip.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _focusNode.requestFocus();
  }

  static double measureHintWidth(String hint, {double fontSize = 15}) {
    final painter = TextPainter(
      text: TextSpan(
        text: hint,
        style: TextStyle(fontSize: fontSize, height: 1.2),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  Future<void> _startVoiceRecord() async {
    if (_recording || _recordBusy) return;
    _hideRecordTip();
    setState(() => _recordBusy = true);
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет доступа к микрофону')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _recordPath = path;
      _recordLevels.clear();
      _recordStartedAt = DateTime.now();
      _recordElapsed = 0;
      _recordTick?.cancel();
      _recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _recordStartedAt == null) return;
        setState(() {
          _recordElapsed =
              DateTime.now().difference(_recordStartedAt!).inSeconds;
        });
      });
      await _ampSub?.cancel();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        // dBFS ≈ −160…0 → уровень 0…15
        final db = amp.current;
        final norm = ((db + 45) / 45).clamp(0.0, 1.0);
        final level = (norm * VoiceHistogram.maxLevel).round();
        _recordLevels.add(level);
        if (_recordLevels.length > 400) {
          _recordLevels.removeRange(0, _recordLevels.length - 400);
        }
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      hideEmojiOverlay();
      if (!mounted) return;
      setState(() {
        _recording = true;
      });
    } catch (e) {
      ApiLogger.instance.logEvent('VOICE', 'start: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось начать запись: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _recordBusy = false);
    }
  }

  Future<void> _cancelVoiceRecord() async {
    _recordTick?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    final path = _recordPath;
    _recordPath = null;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordElapsed = 0;
      _recordLevels.clear();
    });
  }

  Future<void> _finishVoiceRecord({required bool send}) async {
    if (!_recording || _recordBusy) return;
    setState(() => _recordBusy = true);
    _recordTick?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    try {
      final path = await _recorder.stop() ?? _recordPath;
      final started = _recordStartedAt;
      final sec = started == null
          ? _recordElapsed
          : DateTime.now().difference(started).inSeconds;
      _recordPath = null;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordElapsed = 0;
      });
      if (!send || path == null || sec < 1) {
        if (path != null) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        return;
      }
      final hist = _recordLevels.isEmpty
          ? VoiceHistogram.placeholder(durationSec: sec.clamp(1, 3600))
          : VoiceHistogram.downsample(
              List<int>.from(_recordLevels),
              math.min(64, math.max(16, sec * 4)),
            );
      _recordLevels.clear();
      await context.read<AppState>().sendVoiceMessage(
            localPath: path,
            durationSec: sec.clamp(1, 3600),
            histogram: hist,
          );
    } catch (e) {
      ApiLogger.instance.logEvent('VOICE', 'stop: $e');
    } finally {
      if (mounted) setState(() => _recordBusy = false);
    }
  }

  Future<void> _openVideoNote() async {
    hideEmojiOverlay();
    final result = await VideoNoteRecorder.show(context);
    if (result == null || !mounted) return;
    await context.read<AppState>().sendVideoNote(
          localPath: result.path,
          durationSec: result.durationSec,
        );
  }

  String _fmtRec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
    // После закрытия file picker — на следующий кадр, без вложенного await.
    AttachComposerSheet.showLater(context, initialFiles: files);
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
    AttachComposerSheet.showLater(context, initialFiles: files);
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
    AttachComposerSheet.showLater(context, initialFiles: files);
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _recording
                  ? _buildRecordingBar(p)
                  : _buildComposerBar(
                      p,
                      editing: editing != null,
                      replyTo: replyTo != null,
                      hasPending: hasPending,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBar(ForumPalette p) {
    final levels = _recordLevels.isEmpty
        ? List<int>.filled(24, 2)
        : VoiceHistogram.downsample(_recordLevels, 40);
    return Row(
      children: [
        IconButton(
          tooltip: 'Отменить',
          onPressed: _recordBusy ? null : _cancelVoiceRecord,
          icon: Icon(Icons.close_rounded, color: p.text2),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _fmtRec(_recordElapsed),
          style: TextStyle(
            color: p.text1,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 12),
        // Волна: max 168px, при узком чате сжимается (не пропадает и не
        // ломает Row).
        Flexible(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth.clamp(32.0, 168.0);
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: w,
                  height: 28,
                  child: CustomPaint(
                    painter: _LiveWavePainter(
                      levels: levels,
                      color: p.purple,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        _RoundAction(
          color: p.purple,
          icon: Icons.send_rounded,
          onTap: _recordBusy ? null : () => _finishVoiceRecord(send: true),
        ),
      ],
    );
  }

  Widget _buildComposerBar(
    ForumPalette p, {
    required bool editing,
    required bool replyTo,
    required bool hasPending,
  }) {
    final hint = editing
        ? 'Изменить...'
        : (replyTo ? 'Ответ...' : 'Сообщение...');
    // Полный placeholder + небольшой зазор; поле не сжимается уже.
    final hintMinW = measureHintWidth(hint) + _hintGap;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _RoundAction(
          color: p.bg2,
          border: p.border1,
          icon: Icons.attach_file,
          iconColor: editing ? p.text2.withValues(alpha: 0.4) : p.text2,
          onTap: editing ? null : _openAttachMenu,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            constraints: BoxConstraints(
              minHeight: 40,
              maxHeight: 120,
              // Текст поля + кнопка смайла внутри pill.
              minWidth: hintMinW + 40 + 18,
            ),
            decoration: BoxDecoration(
              color: p.bg3,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: hintMinW),
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
                        hintText: hint,
                        hintStyle: TextStyle(color: p.text2, fontSize: 15),
                        hintMaxLines: 1,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                buildEmojiIconButton(
                  palette: p,
                  onEmoji: _insertEmoji,
                  iconSize: _emojiIconSize,
                  enabled: !editing,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Одна кнопка как в Telegram: отправка ↔ голос ↔ видео.
        ValueListenableBuilder<bool>(
          valueListenable: _hasText,
          builder: (context, hasText, _) {
            final showSend = hasText || hasPending || editing;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                return ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: showSend
                  ? _RoundAction(
                      key: const ValueKey('send'),
                      color: p.purple,
                      icon: Icons.send_rounded,
                      iconSize: _iconLg,
                      size: _actionSize,
                      onTap: _send,
                    )
                  : _RoundAction(
                      key: _recordBtnKey,
                      color: p.bg2,
                      border: p.border1,
                      icon: _recordVideoMode
                          ? Icons.videocam_rounded
                          : Icons.mic_none_rounded,
                      iconColor: p.text2,
                      iconSize: _iconLg,
                      size: _actionSize,
                      // Короткий ЛКМ — смена mic ↔ video + чёрная подсказка.
                      onTap: _onRecordModeTap,
                      // Долгое нажатие — запись выбранного типа.
                      onLongPress: () {
                        _hideRecordTip();
                        if (_recordVideoMode) {
                          _openVideoNote();
                        } else {
                          _startVoiceRecord();
                        }
                      },
                    ),
            );
          },
        ),
      ],
    );
  }

  void _onRecordModeTap() {
    setState(() => _recordVideoMode = !_recordVideoMode);
    _showRecordTip();
  }

  void _hideRecordTip() {
    _recordTipTimer?.cancel();
    _recordTipTimer = null;
    _recordTipOverlay?.remove();
    _recordTipOverlay = null;
  }

  String get _recordTipMessage => _recordVideoMode
      ? 'Удерживайте для записи видео.\nНажмите для переключения на голос'
      : 'Удерживайте для записи голоса.\nНажмите для переключения на видео';

  /// Чёрный пузырь как в Telegram. При повторном клике только меняем текст —
  /// без remove/insert, иначе моргает.
  void _showRecordTip() {
    _recordTipText.value = _recordTipMessage;
    _recordTipTimer?.cancel();
    _recordTipTimer = Timer(const Duration(seconds: 3), _hideRecordTip);

    if (_recordTipOverlay != null) {
      _recordTipOverlay!.markNeedsBuild();
      return;
    }

    final box = _recordBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlayState?.context.findRenderObject() as RenderBox?;
    if (box == null ||
        !box.hasSize ||
        overlayState == null ||
        overlayBox == null ||
        !overlayBox.hasSize) {
      return;
    }

    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final btnSize = box.size;

    // Ширина под две полные строки (без переноса третьей).
    const tipMaxW = 340.0;
    const tipPad = 8.0;
    const tipBlockH = 64.0;
    const gapAboveIcon = 14.0;
    var tipLeft = origin.dx + btnSize.width / 2 - tipMaxW / 2;
    tipLeft = tipLeft.clamp(
      tipPad,
      (overlayBox.size.width - tipMaxW - tipPad)
          .clamp(tipPad, overlayBox.size.width),
    );
    _recordTipLeft = tipLeft;
    _recordTipTop = (origin.dy - tipBlockH - gapAboveIcon).clamp(
      tipPad,
      overlayBox.size.height,
    );
    _recordTipArrowX =
        (origin.dx + btnSize.width / 2 - tipLeft).clamp(16.0, tipMaxW - 16);

    _recordTipOverlay = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: _recordTipLeft,
          top: _recordTipTop,
          width: tipMaxW,
          child: IgnorePointer(
            child: ValueListenableBuilder<String>(
              valueListenable: _recordTipText,
              builder: (_, text, __) {
                return _TelegramRecordTip(
                  text: text,
                  arrowCenterX: _recordTipArrowX,
                );
              },
            ),
          ),
        );
      },
    );
    overlayState.insert(_recordTipOverlay!);
  }
}

/// Подсказка записи в стиле Telegram Desktop (тёмный пузырь + стрелка вниз).
class _TelegramRecordTip extends StatelessWidget {
  final String text;
  final double arrowCenterX;

  const _TelegramRecordTip({
    required this.text,
    required this.arrowCenterX,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xE6282828);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 7,
          width: double.infinity,
          child: CustomPaint(
            painter: _TipArrowPainter(
              color: bg,
              tipX: arrowCenterX,
            ),
          ),
        ),
      ],
    );
  }
}

class _TipArrowPainter extends CustomPainter {
  final Color color;
  final double tipX;

  _TipArrowPainter({required this.color, required this.tipX});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(tipX - 7, 0)
      ..lineTo(tipX, size.height)
      ..lineTo(tipX + 7, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TipArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.tipX != tipX;
}

class _RoundAction extends StatelessWidget {
  final Color color;
  final Color? border;
  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _RoundAction({
    super.key,
    required this.color,
    required this.icon,
    this.border,
    this.iconColor = Colors.white,
    this.iconSize = 20,
    this.size = 40,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: CircleBorder(
        side: border != null
            ? BorderSide(color: border!)
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  final List<int> levels;
  final Color color;

  _LiveWavePainter({required this.levels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    final gap = size.width / levels.length;
    final mid = size.height / 2;
    for (var i = 0; i < levels.length; i++) {
      final h = (levels[i] / VoiceHistogram.maxLevel) * (size.height * 0.9);
      final x = i * gap + gap / 2;
      canvas.drawLine(
        Offset(x, mid - h / 2),
        Offset(x, mid + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter oldDelegate) =>
      oldDelegate.levels != levels || oldDelegate.color != color;
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
