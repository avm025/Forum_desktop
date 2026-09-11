import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/media_file.dart';
import '../models/message_view_model.dart';
import '../api/forward_mapper.dart';
import '../api/msg_list_cursors.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'call_message_bubble.dart';
import 'chat_attachment_viewer.dart';
import 'chat_scroll_scope.dart';
import 'delete_message_dialog.dart';
import 'document_attachment_list.dart';
import 'emoji_reactions.dart';
import 'forward_dialog_picker.dart';
import 'location_preview.dart';
import 'media_grid.dart';
import '../utils/attachment_selection.dart';
import '../utils/chat_message_search.dart';
import '../utils/file_saver.dart';
import '../utils/media_display_name.dart';
import '../utils/media_message_layout.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';
import 'file_row_tile.dart';
import 'message_actions_bar.dart';
import 'message_status_list_sheet.dart';
import 'pin_message_dialog.dart';
import 'reply_preview.dart';
import 'status_ticks.dart';
import 'voice_message.dart';

/// Сообщение в ленте: все сообщения слева.
/// В группе — имя и аватар отправителя сверху сообщения.
class MessageItem extends StatefulWidget {
  final MessageViewModel message;
  final bool isGroupChat;
  final String? searchQuery;
  final bool searchHighlightCurrent;
  /// На старте чата не рисуем градиент/иконки-заглушки медиа.
  final bool deferMediaPreview;

  const MessageItem({
    super.key,
    required this.message,
    this.isGroupChat = false,
    this.searchQuery,
    this.searchHighlightCurrent = false,
    this.deferMediaPreview = false,
  });

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  final GlobalKey _bubbleKey = GlobalKey();
  final GlobalKey<LocationPreviewState> _geoKey =
      GlobalKey<LocationPreviewState>();
  List<MediaFile> _selectedAttachments = const [];

  MessageViewModel get message => widget.message;
  bool get _isMine => message.my;
  bool get _clusterTop => message.avaOnTop == true;
  bool get _clusterBottom => message.avaOnBottom == true;

  static const double _avatarSize = 32;
  static const double _avatarGap = 8;
  static const double _headerGap = 6;
  static const double _bubbleRadius = 14;
  static const double _bubbleRadiusSmall = 4;
  static const double _maxBubbleFraction = 0.88;
  static const double _maxBubbleWidthCap = 980;

  double _bubbleMaxWidth(double rowWidth) {
    final cap = (rowWidth * _maxBubbleFraction).clamp(120.0, _maxBubbleWidthCap);
    return rowWidth.clamp(120.0, cap);
  }

  /// Текст подписи в пузыре. Для file/media не подставляем сырой JSON
  /// обмена с сервером (`{"desc":"","files":[...]}`) — только caption.
  String get _textValue {
    if (message.isFile || (message.isImage && message.hasFiles)) {
      final caption = message.desc.trim();
      if (caption.isNotEmpty) return caption;
      final body = message.body.trim();
      if (body.isNotEmpty && !_isAttachmentPayloadJson(body)) return body;
      return '';
    }
    return message.body.isNotEmpty ? message.body : message.text;
  }

  bool get _hasText => _textValue.trim().isNotEmpty;

  static bool _isAttachmentPayloadJson(String value) {
    final t = value.trimLeft();
    if (!t.startsWith('{')) return false;
    return t.contains('"files"') ||
        t.contains('"fname"') ||
        t.contains('"fdir"') ||
        (t.contains('"desc"') && t.contains('"kind"'));
  }

  bool get _isPlainTextOnly =>
      _hasText &&
      !message.hasReply &&
      !message.hasReactions &&
      !message.isVoice &&
      !message.isLocation &&
      !message.isCall &&
      !(message.isImage && message.hasFiles) &&
      !message.isFile;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final useBubbles = state.appearance.messageBubbles;
    final onAccent = _isMine && useBubbles;
    final bubblePadding = useBubbles
        ? _bubblePadding()
        : const EdgeInsets.fromLTRB(2, 2, 2, 2);

    final showHeader = message.showUserName;
    final senderName = _senderDisplayName(state);
    final senderAvatarUrl = _senderAvatarUrl(state);

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: _clusterTop ? 8 : 2,
        bottom: _clusterBottom ? 8 : 2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxBubbleWidth = _bubbleMaxWidth(constraints.maxWidth);
          final innerMaxWidth = maxBubbleWidth - bubblePadding.horizontal;

          final bubbleChild = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.hasReply)
                ReplyPreview(
                  message: message,
                  onAccent: onAccent,
                  maxWidth: innerMaxWidth,
                  currentUserId: state.profile?.id,
                  onTap: message.prn_id.trim().isNotEmpty
                      ? () => ChatScrollScope.maybeOf(context)
                          ?.scrollToMessage(message.prn_id)
                      : null,
                ),
              _content(context, p, onAccent, innerMaxWidth),
              if (message.hasReactions)
                EmojiReactions(
                  reactions: message.emoji,
                  currentUserName: state.profile?.name ?? '',
                  currentUserId: state.profile?.id ?? '',
                  onAccent: onAccent,
                  onReactionTap: _canReact ? _onReactionTap : null,
                ),
              if (!_isPlainTextOnly)
                _footer(p, onAccent, alignEnd: _useWideFooter),
            ],
          );

          final bubble = GestureDetector(
            key: _bubbleKey,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (AttachmentSelection.takeSuppressBubbleTap()) return;
              if (message.isCall) {
                _callbackFromCallMessage(context);
                return;
              }
              final menu = MessageContextMenuController.instance;
              if (menu.isOpenFor(_bubbleKey)) {
                menu.handleBubbleTap(_bubbleKey);
              }
            },
            onSecondaryTapUp: (details) {
              if (AttachmentSelection.takeSuppressBubbleTap()) return;
              _showActions(globalPosition: details.globalPosition);
            },
            child: _Bubble(
              maxWidth: maxBubbleWidth,
              borderRadius: _bubbleBorderRadius(),
              color: useBubbles
                  ? (onAccent ? p.outgoingBubble : p.bg3)
                  : Colors.transparent,
              liquidGlass: useBubbles && state.appearance.liquidGlass,
              opacity: state.appearance.panelOpacity,
              padding: bubblePadding,
              highlightBorder: widget.searchHighlightCurrent,
              highlightColor: onAccent ? p.lime : p.purple,
              flat: !useBubbles,
              child: bubbleChild,
            ),
          );

          return Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHeader) ...[
                    _SenderHeader(
                      name: senderName,
                      avatarUrl: senderAvatarUrl,
                      avatarColor: _isMine
                          ? state.currentUserAvatarHex(isDark: state.isDark)
                          : state.selectedDialog?.avatarColor,
                      colAvaId: _isMine
                          ? state.appearance.avatarColorId
                          : (state.selectedDialog?.colAvaId ?? 1),
                      nameColor: state.nameColor(isDark: state.isDark),
                      avatarSize: _avatarSize,
                      gap: _avatarGap,
                    ),
                    const SizedBox(height: _headerGap),
                  ],
                  bubble,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _senderDisplayName(AppState state) {
    if (_isMine) {
      final me = state.profile?.name.trim() ?? '';
      if (me.isNotEmpty) return me;
    }
    final name = message.fr_name.trim();
    if (name.isNotEmpty) return name;
    // В личном чате имя собеседника часто только в карточке диалога.
    final peer = state.selectedDialog?.chatName.trim() ?? '';
    return peer.isNotEmpty ? peer : 'Пользователь';
  }

  String _senderAvatarUrl(AppState state) {
    if (_isMine) {
      return state.profile?.displayAvatarUrl.trim() ?? '';
    }
    final fromMsg = message.preview.trim();
    if (fromMsg.isNotEmpty) return fromMsg;
    // Личный чат / пустой preview у media|voice|file — аватар из карточки диалога.
    return state.selectedDialog?.avatar.trim() ?? '';
  }

  bool get _useWideFooter =>
      message.isVoice ||
      message.isLocation ||
      message.isCall ||
      (message.isImage && message.hasFiles) ||
      message.isFile;

  BorderRadius _bubbleBorderRadius() {
    // Все сообщения слева: «хвост» у нижнего левого угла кластера.
    return BorderRadius.only(
      topLeft: Radius.circular(
        _clusterTop ? _bubbleRadius : _bubbleRadiusSmall,
      ),
      topRight: const Radius.circular(_bubbleRadius),
      bottomLeft: Radius.circular(
        _clusterBottom ? _bubbleRadius : _bubbleRadiusSmall,
      ),
      bottomRight: const Radius.circular(_bubbleRadius),
    );
  }

  EdgeInsets _bubblePadding() {
    final mediaOnly = (message.isImage && message.hasFiles) &&
        message.body.isEmpty &&
        message.text.isEmpty;
    if (mediaOnly) {
      return const EdgeInsets.fromLTRB(3, 3, 3, 6);
    }
    return const EdgeInsets.fromLTRB(10, 8, 10, 6);
  }

  bool get _canReact => MsgListCursors.isSavedMessage(message);

  @override
  void dispose() {
    MessageContextMenuController.instance.closeIfOpenFor(_bubbleKey);
    super.dispose();
  }

  void _onReactionTap(String emoji, {required bool remove}) {
    if (!_canReact) return;
    unawaited(
      context.read<AppState>().toggleReaction(message, emoji, remove: remove),
    );
  }

  void _pickReaction(String emoji) {
    if (!_canReact) return;
    unawaited(context.read<AppState>().toggleReaction(message, emoji));
  }

  Future<void> _openFile(BuildContext context, MediaFile file) async {
    try {
      await MediaFileLoader.ensureCached(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
    } catch (_) {}
    if (!context.mounted) return;
    await ChatAttachmentViewer.show(context, file);
  }

  void _onMediaSelectionChanged(List<MediaFile> selected) {
    _selectedAttachments = List<MediaFile>.from(selected);
    // ЛКМ только выделяет; меню — по ПКМ. Пустое выделение закрывает меню.
    if (selected.isEmpty) {
      MessageContextMenuController.instance.closeIfOpenFor(_bubbleKey);
    }
  }

  bool get _canSaveAsCandidate {
    if (message.isCall) return false;
    if (message.isLocation &&
        message.latitude != null &&
        message.longitude != null) {
      return true;
    }
    return message.files.isNotEmpty ||
        ((message.isImage || message.isFile) &&
            ((message.fileTitle ?? '').trim().isNotEmpty ||
                message.url.trim().isNotEmpty ||
                message.fdir.trim().isNotEmpty));
  }

  List<MediaFile> _filesForSave() {
    if (_selectedAttachments.isNotEmpty) {
      return List<MediaFile>.from(_selectedAttachments);
    }
    if (message.files.isNotEmpty) {
      return List<MediaFile>.from(message.files);
    }
    // Legacy single-file message without files[].
    return [_legacyMediaFile()];
  }

  /// Как у картинок: достаточно URL или локальной копии (в т.ч. пересланные).
  Future<bool> _isSaveableAttachment(MediaFile file) async {
    if (await MediaFileLoader.isDownloaded(file)) return true;
    final url = MediaFileUrl.resolve(file);
    return url.trim().isNotEmpty;
  }

  Future<List<MediaFile>> _downloadedFilesForSave() async {
    final out = <MediaFile>[];
    for (final file in _filesForSave()) {
      if (await _isSaveableAttachment(file)) {
        out.add(file);
      }
    }
    return out;
  }

  Future<void> _saveAs() async {
    if (message.isLocation) {
      await _saveGeoPreview();
      return;
    }

    final files = await _downloadedFilesForSave();
    if (files.isEmpty || !mounted) return;

    var saved = 0;
    var failed = 0;
    for (final file in files) {
      final result = await FileSaver.save(file);
      if (result == FileSaveResult.saved) {
        saved++;
      } else if (result == FileSaveResult.failed) {
        failed++;
      } else {
        // cancelled — прерываем серию
        break;
      }
    }
    if (!mounted) return;
    if (saved == 0 && failed == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    if (failed > 0 && saved == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить файл')),
      );
    } else if (saved > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved == 1 ? 'Файл сохранён' : 'Сохранено файлов: $saved',
          ),
        ),
      );
    }
  }

  Future<void> _saveGeoPreview() async {
    final geo = _geoKey.currentState;
    final png = await geo?.captureMapPng();
    if (png == null || png.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить карту')),
      );
      return;
    }
    final result = await FileSaver.saveBytes(
      bytes: png,
      fileName: 'map.png',
    );
    if (!mounted) return;
    if (result == FileSaveResult.saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл сохранён')),
      );
    } else if (result == FileSaveResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить файл')),
      );
    }
  }

  void _onAttachmentContextMenu(Offset globalPosition) {
    unawaited(_showActions(globalPosition: globalPosition));
  }

  /// Открытие вложения: докачать при необходимости (как картинки/видео).
  Future<void> _openAttachment(
    BuildContext context,
    MediaFile file,
  ) async {
    try {
      await MediaFileLoader.ensureCached(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
    } catch (_) {}
    if (!context.mounted) return;
    await ChatAttachmentViewer.show(context, file);
  }

  MediaFile _legacyMediaFile() {
    if (message.files.isNotEmpty) return message.files.first;
    final title = MediaDisplayName.resolve(
      title: message.fileTitle,
      dttmcr: message.dttmcr,
    );
    final file = MediaFile(
      url: message.url,
      fdir: message.fdir,
      fname: title,
      title: title,
    );
    if (file.url.trim().isEmpty) {
      file.url = MediaFileUrl.resolve(file);
    }
    return file;
  }

  String? get _copyText {
    final value = _textValue.trim();
    if (value.isNotEmpty) return value;
    if (message.files.isNotEmpty) {
      return MediaDisplayName.forFile(
        message.files.first,
        dttmcr: message.dttmcr,
      );
    }
    if ((message.fileTitle ?? '').trim().isNotEmpty) {
      return MediaDisplayName.resolve(
        title: message.fileTitle,
        dttmcr: message.dttmcr,
      );
    }
    return null;
  }

  Future<void> _showActions({Offset? globalPosition}) async {
    final copyText = message.isCall ? null : _copyText;
    final appState = context.read<AppState>();
    final dialog = appState.selectedDialog;
    final isGroup = dialog?.isGrp == true;
    final msgId = appState.serverMessageId(message);
    final dlgId = dialog?.id?.trim() ?? '';
    final showViews = message.my &&
        message.status >= 2 &&
        msgId != null &&
        dlgId.isNotEmpty &&
        dlgId != '0';
    final canPin = msgId != null && dlgId.isNotEmpty && dlgId != '0';
    final pinned = canPin && appState.isMessagePinned(dlgId, msgId);
    final canSaveAs = message.isLocation
        ? _canSaveAsCandidate
        : (_canSaveAsCandidate &&
            (await _downloadedFilesForSave()).isNotEmpty);
    if (!mounted) return;

    await showMessageActions(
      context: context,
      anchorKey: _bubbleKey,
      globalPosition: globalPosition,
      reactions: message.isCall || !_canReact
          ? const []
          : appState.quickReactions,
      onReaction: message.isCall || !_canReact ? null : _pickReaction,
      onReply: () => appState.setReplyTo(message),
      onForward: message.isCall
          ? null
          : (ForwardMapper.canForward(message)
              ? () => _forward(context)
              : null),
      onEdit: message.my &&
              !message.isCall &&
              appState.canEditMessage(message)
          ? () => appState.setEditMessage(message)
          : null,
      onCopy: copyText == null
          ? null
          : () => Clipboard.setData(ClipboardData(text: copyText)),
      onSaveAs: canSaveAs ? () => unawaited(_saveAs()) : null,
      onFavorite: message.isCall
          ? null
          : () async {
              try {
                await appState.sendToFavorites(message);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Добавлено в избранное')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), ''),
                    ),
                  ),
                );
              }
            },
      onSelect: null, // как iOS — пункт есть, но disabled
      onPin: canPin
          ? () async {
              final peerName = dialog?.chatName.trim();
              final result = pinned
                  ? await showUnpinMessageDialog(
                      context: context,
                      isGroupChat: isGroup,
                      peerName: peerName,
                    )
                  : await showPinMessageDialog(
                      context: context,
                      isGroupChat: isGroup,
                      peerName: peerName,
                    );
              if (result == null || !mounted) return;
              try {
                await appState.togglePinMessage(
                  message,
                  forBoth: result.forBoth,
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), ''),
                    ),
                  ),
                );
              }
            }
          : null,
      isPinned: pinned,
      onDelete: () => _confirmDelete(context),
      readViews: showViews
          ? MsgReadViewsConfig(
              isGroup: isGroup,
              load: () => appState.fetchMsgReadList(
                dlgId: dlgId,
                msgId: msgId,
              ),
              avatarColors: (entry) {
                final id = entry.colAvaId;
                if (id == null) return null;
                final palette = appState.database.avatarById(id);
                if (palette == null) return null;
                return palette
                    .hexForDark(appState.isDark)
                    .map((h) => h.startsWith('#') ? h : '#$h')
                    .toList();
              },
            )
          : null,
      onViews: isGroup
          ? (entries) {
              if (!context.mounted) return;
              MessageStatusListSheet.show(context, entries: entries);
            }
          : null,
    );
  }

  Future<void> _callbackFromCallMessage(BuildContext context) async {
    final video = message.callBody?.isVideo ?? false;
    await context.read<AppState>().startCallFromChat(video: video);
  }

  Future<void> _forward(BuildContext context) async {
    final appState = context.read<AppState>();
    await ForwardDialogPicker.show(
      context,
      message: message,
      excludeDlgId: appState.selectedDialog?.id,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final appState = context.read<AppState>();
    final dialog = appState.selectedDialog;
    if (dialog == null) return;

    final result = await showDeleteMessageDialog(
      context: context,
      isOwnMessage: message.my,
      isGroupChat: dialog.isGrp,
      peerName: dialog.chatName,
    );
    if (result == null || !context.mounted) return;

    appState.deleteMessage(
      message.id,
      forEveryone: result.forEveryone,
    );
  }

  Widget _content(
    BuildContext context,
    ForumPalette p,
    bool onAccent,
    double innerMaxWidth,
  ) {
    if (message.isCall) {
      final state = context.read<AppState>();
      final display = message.callDisplay(currentUserId: state.profile?.id);
      if (display == null) {
        return Text(
          message.desc.isNotEmpty ? message.desc : 'Вызов',
          style: TextStyle(
            color: onAccent ? Colors.white : p.text1,
            fontSize: 15,
          ),
        );
      }
      return CallMessageBubble(
        display: display,
        onAccent: onAccent,
        maxWidth: innerMaxWidth,
      );
    }
    if (message.isVoice) {
      return VoiceMessage(message: message, onAccent: onAccent);
    }
    if (message.isLocation) {
      return LocationPreview(
        key: _geoKey,
        message: message,
        maxWidth: innerMaxWidth,
        onContextMenu: _onAttachmentContextMenu,
      );
    }
    if (message.isImage && message.hasFiles) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaGrid(
            files: message.files,
            maxWidth: innerMaxWidth,
            deferPreview: widget.deferMediaPreview,
            onFileTap: (file) => _openFile(context, file),
            onSelectionChanged: _onMediaSelectionChanged,
            onContextMenu: _onAttachmentContextMenu,
          ),
          if (_hasText)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              // Подпись; «изменено» + дата — в футере ниже, как в Telegram.
              child: _text(p, onAccent, innerMaxWidth),
            ),
        ],
      );
    }
    if (message.isFile) {
      return _fileContent(context, p, onAccent, innerMaxWidth);
    }
    if (_isPlainTextOnly) {
      return _textWithFooter(p, onAccent, innerMaxWidth);
    }
    return _text(p, onAccent, innerMaxWidth);
  }

  Widget _fileContent(
    BuildContext context,
    ForumPalette p,
    bool onAccent,
    double innerMaxWidth,
  ) {
    final files = message.files.take(MediaMessageLayout.maxFiles).toList();
    if (files.isEmpty) {
      return _legacyFileTile(p, onAccent);
    }

    return DocumentAttachmentList(
      files: files,
      onAccent: onAccent,
      maxWidth: innerMaxWidth,
      onOpen: (file) => _openAttachment(context, file),
      onSelectionChanged: _onMediaSelectionChanged,
      onContextMenu: _onAttachmentContextMenu,
      // Подпись; «изменено» + дата — в футере пузыря ниже.
      footer: _hasText ? _text(p, onAccent, innerMaxWidth) : null,
    );
  }

  Widget _text(ForumPalette p, bool onAccent, double maxWidth) {
    if (!_hasText) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _MessageBodyText(
        text: _textValue,
        style: TextStyle(
          color: onAccent ? Colors.white : p.text1,
          fontSize: 15,
          height: 1.35,
        ),
        searchQuery: widget.searchQuery,
        highlightColor: onAccent ? p.lime.withValues(alpha: 0.45) : p.purple.withValues(alpha: 0.35),
        onSimpleTap: _onTextSimpleTap,
        onSecondaryTap: (pos) => unawaited(_showActions(globalPosition: pos)),
      ),
    );
  }

  Widget _textWithFooter(ForumPalette p, bool onAccent, double maxWidth) {
    if (!_hasText) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _MessageBodyText(
        text: _textValue,
        style: TextStyle(
          color: onAccent ? Colors.white : p.text1,
          fontSize: 15,
          height: 1.35,
        ),
        searchQuery: widget.searchQuery,
        highlightColor: onAccent ? p.lime.withValues(alpha: 0.45) : p.purple.withValues(alpha: 0.35),
        footer: _footerMeta(p, onAccent),
        onSimpleTap: _onTextSimpleTap,
        onSecondaryTap: (pos) => unawaited(_showActions(globalPosition: pos)),
      ),
    );
  }

  void _onTextSimpleTap() {
    if (message.isCall) {
      _callbackFromCallMessage(context);
      return;
    }
    // ЛКМ по тексту меню не открывает.
    final menu = MessageContextMenuController.instance;
    if (menu.isOpenFor(_bubbleKey)) {
      menu.handleBubbleTap(_bubbleKey);
    }
  }

  Widget _footer(ForumPalette p, bool onAccent, {required bool alignEnd}) {
    final meta = _footerMeta(p, onAccent);
    if (!alignEnd) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: meta,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: meta,
      ),
    );
  }

  Widget _footerMeta(ForumPalette p, bool onAccent) {
    final timeColor = onAccent ? Colors.white70 : p.text2;
    final tickColor = onAccent ? Colors.white70 : p.text2;
    final readTickColor = onAccent ? p.lime : p.lime;
    final edited = message.isEdited;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isMine) ...[
          StatusTicks(
            status: message.status,
            size: 14,
            color: tickColor,
            readColor: readTickColor,
          ),
          const SizedBox(width: 4),
        ],
        if (edited) ...[
          Text(
            'изменено',
            style: TextStyle(
              color: timeColor,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          message.dtshow,
          style: TextStyle(color: timeColor, fontSize: 11),
        ),
      ],
    );
  }

  Widget _legacyFileTile(ForumPalette p, bool onAccent) {
    final file = _legacyMediaFile();
    return FileRowTile(
      file: file,
      onAccent: onAccent,
      maxWidth: 260,
      onTap: () => _openAttachment(context, file),
    );
  }
}

class _Bubble extends StatelessWidget {
  final double maxWidth;
  final BorderRadius borderRadius;
  final Color color;
  final EdgeInsets padding;
  final Widget child;
  final bool liquidGlass;
  final double opacity;
  final bool highlightBorder;
  final Color? highlightColor;
  final bool flat;

  const _Bubble({
    required this.maxWidth,
    required this.borderRadius,
    required this.color,
    required this.padding,
    required this.child,
    this.liquidGlass = false,
    this.opacity = 1,
    this.highlightBorder = false,
    this.highlightColor,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    if (flat) {
      Widget content = Padding(
        padding: padding,
        child: child,
      );
      if (highlightBorder && highlightColor != null) {
        content = DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: highlightColor!, width: 2),
            borderRadius: borderRadius,
          ),
          child: content,
        );
      }
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: IntrinsicWidth(child: content),
      );
    }

    final fill = color.withValues(alpha: liquidGlass ? opacity : 1.0);
    Widget bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (liquidGlass) {
      bubble = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: bubble,
        ),
      );
    }

    if (highlightBorder && highlightColor != null) {
      bubble = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: highlightColor!, width: 2),
          borderRadius: borderRadius,
        ),
        child: bubble,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: IntrinsicWidth(
        child: bubble,
      ),
    );
  }
}

class _SenderHeader extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final List<String>? avatarColor;
  final int colAvaId;
  final Color nameColor;
  final double avatarSize;
  final double gap;

  const _SenderHeader({
    required this.name,
    required this.avatarUrl,
    required this.nameColor,
    required this.avatarSize,
    required this.gap,
    this.avatarColor,
    this.colAvaId = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvatarWidget(
          name: name,
          avatarUrl: avatarUrl,
          avatarColor: avatarColor,
          colAvaId: colAvaId,
          size: avatarSize,
        ),
        SizedBox(width: gap),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: nameColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Текст сообщения: drag — выделение без системного toolbar.
/// ПКМ / простой тап обрабатываются отдельно (SelectableText глотает secondary).
class _MessageBodyText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Widget? footer;
  final String? searchQuery;
  final Color? highlightColor;
  final VoidCallback onSimpleTap;
  final void Function(Offset globalPosition) onSecondaryTap;

  const _MessageBodyText({
    required this.text,
    required this.style,
    this.footer,
    this.searchQuery,
    this.highlightColor,
    required this.onSimpleTap,
    required this.onSecondaryTap,
  });

  @override
  State<_MessageBodyText> createState() => _MessageBodyTextState();
}

class _MessageBodyTextState extends State<_MessageBodyText> {
  static const _dragSlop = 6.0;

  Offset? _downGlobal;
  bool _dragged = false;
  bool _secondary = false;

  void _onPointerDown(PointerDownEvent e) {
    _downGlobal = e.position;
    _dragged = false;
    _secondary = e.buttons == kSecondaryMouseButton;
    if (_secondary) {
      // SelectableText перехватывает GestureDetector.onSecondaryTapUp.
      widget.onSecondaryTap(e.position);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final start = _downGlobal;
    if (start == null || _dragged) return;
    if ((e.position - start).distance > _dragSlop) {
      _dragged = true;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final wasDrag = _dragged;
    final wasSecondary = _secondary;
    _downGlobal = null;
    _dragged = false;
    _secondary = false;
    // ЛКМ без drag — закрытие открытого меню; ПКМ уже обработан в down.
    if (!wasDrag && !wasSecondary) {
      widget.onSimpleTap();
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _downGlobal = null;
    _dragged = false;
    _secondary = false;
  }

  Widget _buildVisibleText() {
    final query = widget.searchQuery?.trim();
    if (query == null || query.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final parts = ChatMessageSearch.highlightParts(widget.text, query);
    final highlight = widget.highlightColor ??
        (widget.style.color ?? Colors.white).withValues(alpha: 0.35);

    return Text.rich(
      TextSpan(
        children: [
          for (final part in parts)
            TextSpan(
              text: part.text,
              style: widget.style.copyWith(
                backgroundColor: part.match ? highlight : null,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStack = Stack(
      children: [
        _buildVisibleText(),
        SelectableText(
          widget.text,
          style: widget.style.copyWith(color: Colors.transparent),
          selectionColor: (widget.style.color ?? Colors.white)
              .withValues(alpha: 0.35),
          contextMenuBuilder: (context, editableTextState) =>
              const SizedBox.shrink(),
          magnifierConfiguration: TextMagnifierConfiguration.disabled,
        ),
      ],
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      // Как в Telegram: мета («изменено» + дата) под текстом справа.
      child: widget.footer == null
          ? textStack
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                textStack,
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: widget.footer,
                ),
              ],
            ),
    );
  }
}
