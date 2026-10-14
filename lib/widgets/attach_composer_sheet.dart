import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_file.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/chat_file_dnd.dart';
import '../utils/emoticon_replacer.dart';
import '../utils/file_kind.dart';
import '../utils/media_display_name.dart';
import '../utils/media_message_layout.dart';
import 'telegram_emoji_overlay.dart';

/// Окно как в Telegram: файлы → подпись → «ещё» → отправка (не сразу).
class AttachComposerSheet {
  AttachComposerSheet._();

  /// Показать после завершения drop/picker — не из колбэка DnD напрямую.
  static void showLater(
    BuildContext context, {
    required List<MediaFile> initialFiles,
  }) {
    final files = initialFiles.take(MediaMessageLayout.maxFiles).toList();
    if (files.isEmpty) return;
    // После кадра: иначе macOS DnD ждёт onPerformDrop и зависает на модалке.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(show(context, initialFiles: files));
    });
  }

  static Future<void> show(
    BuildContext context, {
    required List<MediaFile> initialFiles,
  }) async {
    final files = initialFiles.take(MediaMessageLayout.maxFiles).toList();
    if (files.isEmpty) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _AttachComposerDialog(initialFiles: files),
    );
  }
}

class _AttachComposerDialog extends StatefulWidget {
  final List<MediaFile> initialFiles;

  const _AttachComposerDialog({required this.initialFiles});

  @override
  State<_AttachComposerDialog> createState() => _AttachComposerDialogState();
}

class _AttachComposerDialogState extends State<_AttachComposerDialog>
    with TelegramEmojiOverlayHost {
  late final List<MediaFile> _files;
  final _caption = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  /// «Как медиафайл» — иначе отправка type=file.
  late bool _sendAsMedia;
  /// Без сжатия (оригинал).
  bool _noCompression = false;
  /// Отправлять фото в высоком качестве.
  bool _highQuality = false;

  static const _emojiIconSize = 26.4; // как в панели ввода чата

  bool get _hasOnlyMedia =>
      _files.isNotEmpty && _files.every(ChatFileDnd.isMediaAttachment);

  @override
  void initState() {
    super.initState();
    _files = List<MediaFile>.from(widget.initialFiles);
    _sendAsMedia = _files.every(ChatFileDnd.isMediaAttachment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    disposeEmojiOverlay();
    _caption.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    final text = _caption.text;
    final sel = _caption.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, emoji);
    _caption.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _focus.requestFocus();
  }

  @override
  Future<void> hideEmojiOverlay() async {
    await super.hideEmojiOverlay();
    if (mounted) _focus.requestFocus();
  }

  String get _title {
    final n = _files.length;
    final mod10 = n % 10;
    final mod100 = n % 100;
    final asMedia = _sendAsMedia && _hasOnlyMedia;
    if (asMedia) {
      if (mod10 == 1 && mod100 != 11) return '$n медиа';
      return '$n медиа';
    }
    if (mod10 == 1 && mod100 != 11) return '$n файл';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$n файла';
    }
    return '$n файлов';
  }

  Future<void> _addMore() async {
    final room = MediaMessageLayout.maxFiles - _files.length;
    if (room <= 0) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final added = <MediaFile>[];
    for (final f in result.files.take(room)) {
      final kind = FileKind.kindFromName(f.name);
      final mediaProbe = MediaFile(fname: f.name, kind: kind);
      final isMedia = ChatFileDnd.isMediaAttachment(mediaProbe);
      added.add(MediaFile(
        fname: f.name,
        title: f.name,
        kind: kind,
        size: f.size,
        bytes: f.bytes,
        URL: f.path,
        width: isMedia ? '248' : '0',
        height: isMedia ? '248' : '0',
      ));
    }
    if (added.isEmpty) return;
    setState(() {
      _files.addAll(added);
      if (!_hasOnlyMedia) _sendAsMedia = false;
    });
  }

  Future<void> _send() async {
    if (_sending || _files.isEmpty) return;
    setState(() => _sending = true);
    final caption = EmoticonReplacer.replace(_caption.text.trim());
    final batch = List<MediaFile>.from(_files);
    final asMedia = _sendAsMedia && _hasOnlyMedia;
    final state = context.read<AppState>();
    Navigator.of(context).pop();
    try {
      await state.sendAttachmentBatch(
        batch,
        caption: caption,
        sendAsMedia: asMedia,
        noCompression: _noCompression,
        highQuality: _highQuality,
      );
    } catch (_) {}
  }

  Widget _menuCheck(bool on) {
    return SizedBox(
      width: 22,
      child: on
          ? Icon(Icons.check_rounded, size: 18, color: context.palette.purple)
          : null,
    );
  }

  void _removeAt(int index) {
    setState(() {
      _files.removeAt(index);
      if (_files.isEmpty) Navigator.of(context).pop();
    });
  }

  Widget _buildAttachCard(ForumPalette p, double listMaxH) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: p.bg1,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                    color: p.text1,
                    bg: p.bg3,
                  ),
                  Expanded(
                    child: Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Ещё',
                    offset: const Offset(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (v) {
                      if (v == 'as_media') {
                        if (!_hasOnlyMedia) return;
                        setState(() => _sendAsMedia = !_sendAsMedia);
                      } else if (v == 'no_compress') {
                        setState(() {
                          _noCompression = !_noCompression;
                          if (_noCompression) _highQuality = false;
                        });
                      } else if (v == 'hd') {
                        setState(() {
                          _highQuality = !_highQuality;
                          if (_highQuality) _noCompression = false;
                        });
                      } else if (v == 'add') {
                        _addMore();
                      }
                    },
                    itemBuilder: (_) {
                      final canMedia = _hasOnlyMedia;
                      return [
                        PopupMenuItem(
                          value: 'as_media',
                          enabled: canMedia,
                          child: Row(
                            children: [
                              _menuCheck(canMedia && _sendAsMedia),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('Как медиафайл')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'no_compress',
                          child: Row(
                            children: [
                              _menuCheck(_noCompression),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('Без сжатия')),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'hd',
                          enabled: canMedia && _sendAsMedia,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: Icon(
                                  Icons.hd_outlined,
                                  size: 20,
                                  color: _highQuality ? p.purple : p.text2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Отправлять фото в высоком качестве',
                                ),
                              ),
                              if (_highQuality)
                                Icon(Icons.check_rounded,
                                    size: 18, color: p.purple),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'add',
                          enabled:
                              _files.length < MediaMessageLayout.maxFiles,
                          child: const Row(
                            children: [
                              SizedBox(width: 22),
                              SizedBox(width: 8),
                              Expanded(child: Text('Добавить файлы…')),
                            ],
                          ),
                        ),
                      ];
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: p.bg3,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 20,
                        color: p.text1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listMaxH),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  return _FileRow(
                    file: _files[i],
                    onRemove: () => _removeAt(i),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.bg3,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _caption,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              style: TextStyle(color: p.text1, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Добавить подпись…',
                                hintStyle: TextStyle(
                                  color: p.text3,
                                  fontSize: 15,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          buildEmojiIconButton(
                            palette: p,
                            onEmoji: _insertEmoji,
                            iconSize: _emojiIconSize,
                            placement: TelegramEmojiPlacement.besideCard,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: p.purple,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _send,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    final listMaxH = (screenH * 0.4).clamp(120.0, 320.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      // Ключ карточки — модалка смайлов открывается справа от неё.
      child: KeyedSubtree(
        key: emojiBesideKey,
        child: _buildAttachCard(p, listMaxH),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color bg;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final MediaFile file;
  final VoidCallback onRemove;

  const _FileRow({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = MediaDisplayName.forFile(file);
    final isMedia = ChatFileDnd.isMediaAttachment(file);
    final path = (file.URL ?? '').trim();
    // Не трогаем existsSync на UI — только иконка / лёгкий decode.
    final showThumb = isMedia &&
        path.isNotEmpty &&
        !path.startsWith('http') &&
        !FileKind.isVideoKind(file.kind);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(isMedia ? 10 : 22),
          child: SizedBox(
            width: 44,
            height: 44,
            child: showThumb
                ? Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 88,
                    errorBuilder: (_, __, ___) => _iconBox(p, isMedia),
                  )
                : _iconBox(p, isMedia),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.text1,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                file.humanSize,
                style: TextStyle(color: p.text2, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Убрать',
          onPressed: onRemove,
          icon: Icon(Icons.close_rounded, color: p.text3, size: 18),
        ),
      ],
    );
  }

  Widget _iconBox(ForumPalette p, bool isMedia) {
    return ColoredBox(
      color: p.purple,
      child: Icon(
        isMedia
            ? (FileKind.isVideoKind(file.kind)
                ? Icons.videocam_rounded
                : Icons.image_rounded)
            : Icons.insert_drive_file_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}
