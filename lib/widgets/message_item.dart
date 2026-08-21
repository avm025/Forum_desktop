import 'dart:async';
import 'dart:ui';

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
import '../utils/media_message_layout.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';
import 'file_row_tile.dart';
import 'message_actions_bar.dart';
import 'message_status_list_sheet.dart';
import 'reply_preview.dart';
import 'status_ticks.dart';
import 'voice_message.dart';

/// Сообщение в ленте: свои справа (фиолетовый пузырь), чужие слева (серый).
class MessageItem extends StatefulWidget {
  final MessageViewModel message;
  final bool isGroupChat;

  const MessageItem({
    super.key,
    required this.message,
    this.isGroupChat = false,
  });

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  final GlobalKey _bubbleKey = GlobalKey();

  MessageViewModel get message => widget.message;
  bool get _isMine => message.my;
  bool get _clusterTop => message.avaOnTop == true;
  bool get _clusterBottom => message.avaOnBottom == true;

  static const double _avatarSize = 32;
  static const double _avatarGap = 8;
  static const double _bubbleRadius = 14;
  static const double _bubbleRadiusSmall = 4;
  static const double _maxBubbleFraction = 0.88;
  static const double _maxBubbleWidthCap = 980;

  double _maxBubbleWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * _maxBubbleFraction).clamp(120.0, _maxBubbleWidthCap);
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
    final maxBubbleWidth = _maxBubbleWidth(context);
    final onAccent = _isMine;
    final bubblePadding = _bubblePadding();
    final innerMaxWidth = maxBubbleWidth - bubblePadding.horizontal;

    final showAvatar = widget.isGroupChat && !_isMine && _clusterTop;
    final continuationIndent = widget.isGroupChat && !_isMine && !_clusterTop;

    final bubble = GestureDetector(
      key: _bubbleKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (message.isCall) {
          _callbackFromCallMessage(context);
          return;
        }
        final menu = MessageContextMenuController.instance;
        if (menu.isOpenFor(_bubbleKey)) {
          menu.handleBubbleTap(_bubbleKey);
          return;
        }
        // ЛКМ — открыть окно действий/реакций (как раньше на desktop).
        _showActions();
      },
      onSecondaryTapUp: (details) =>
          _showActions(globalPosition: details.globalPosition),
      onLongPress: _showActions,
      child: _Bubble(
        maxWidth: maxBubbleWidth,
        borderRadius: _bubbleBorderRadius(),
        color: onAccent ? p.outgoingBubble : p.bg3,
        liquidGlass: state.appearance.liquidGlass,
        opacity: state.appearance.panelOpacity,
        padding: bubblePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.showUserName && !_isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.fr_name,
                  style: TextStyle(
                    color: state.nameColor(isDark: state.isDark),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
            if (!_isPlainTextOnly) _footer(p, onAccent, alignEnd: _useWideFooter),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: _clusterTop ? 6 : 2,
        bottom: _clusterBottom ? 6 : 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            _isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!_isMine) ...[
            if (showAvatar) ...[
              AvatarWidget(
                name: message.fr_name,
                avatarUrl: message.preview,
                size: _avatarSize,
              ),
              const SizedBox(width: _avatarGap),
            ] else if (continuationIndent)
              const SizedBox(width: _avatarSize + _avatarGap),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: bubble,
          ),
        ],
      ),
    );
  }

  bool get _useWideFooter =>
      message.isVoice ||
      message.isLocation ||
      message.isCall ||
      (message.isImage && message.hasFiles) ||
      message.isFile;

  BorderRadius _bubbleBorderRadius() {
    if (_isMine) {
      return BorderRadius.only(
        topLeft: const Radius.circular(_bubbleRadius),
        topRight: Radius.circular(
          _clusterTop ? _bubbleRadius : _bubbleRadiusSmall,
        ),
        bottomLeft: const Radius.circular(_bubbleRadius),
        bottomRight: const Radius.circular(_bubbleRadiusSmall),
      );
    }
    return BorderRadius.only(
      topLeft: Radius.circular(
        _clusterTop ? _bubbleRadius : _bubbleRadiusSmall,
      ),
      topRight: const Radius.circular(_bubbleRadius),
      bottomLeft: const Radius.circular(_bubbleRadiusSmall),
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

  bool get _canOpen =>
      message.isFile || (message.isImage && message.hasFiles);

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
    await ChatAttachmentViewer.show(context, file);
  }

  /// Документы: открытие только если файл уже загружен («Загрузить»).
  Future<void> _openDocumentIfDownloaded(
    BuildContext context,
    MediaFile file,
  ) async {
    if (!await MediaFileLoader.isDownloaded(file)) return;
    if (!context.mounted) return;
    await ChatAttachmentViewer.show(context, file);
  }

  MediaFile _legacyMediaFile() {
    if (message.files.isNotEmpty) return message.files.first;
    final fname = message.fileTitle ?? '';
    final file = MediaFile(
      url: message.url,
      fdir: message.fdir,
      fname: fname.isNotEmpty ? fname : 'document',
      title: message.fileTitle ?? '',
    );
    if (file.url.trim().isEmpty) {
      file.url = MediaFileUrl.resolve(file);
    }
    return file;
  }

  String? get _copyText {
    final value = _textValue.trim();
    if (value.isNotEmpty) return value;
    if ((message.fileTitle ?? '').trim().isNotEmpty) {
      return message.fileTitle!.trim();
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

    await showMessageActions(
      context: context,
      anchorKey: _bubbleKey,
      globalPosition: globalPosition,
      reactions: message.isCall || !_canReact
          ? const []
          : appState.quickReactions,
      onReaction: message.isCall || !_canReact ? null : _pickReaction,
      onCall: message.isCall
          ? () => _callbackFromCallMessage(context)
          : null,
      onReply: () => appState.setReplyTo(message),
      onForward: message.isCall
          ? null
          : (ForwardMapper.canForward(message)
              ? () => _forward(context)
              : null),
      onCopy: copyText == null
          ? null
          : () => Clipboard.setData(ClipboardData(text: copyText)),
      onOpen: message.isCall
          ? null
          : (_canOpen && message.files.isNotEmpty
              ? () => _openFile(context, message.files.first)
              : null),
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
      return LocationPreview(message: message);
    }
    if (message.isImage && message.hasFiles) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaGrid(
            files: message.files,
            maxWidth: innerMaxWidth,
            onFileTap: (file) => _openFile(context, file),
          ),
          if (_hasText)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _textWithFooter(p, onAccent, innerMaxWidth),
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
      onOpen: (file) => _openDocumentIfDownloaded(context, file),
      footer: _hasText
          ? _textWithFooter(p, onAccent, innerMaxWidth)
          : null,
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
        onSimpleTap: _onTextSimpleTap,
      ),
    );
  }

  Widget _textWithFooter(ForumPalette p, bool onAccent, double maxWidth) {
    if (!_hasText) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _MessageBodyText(
            text: _textValue,
            style: TextStyle(
              color: onAccent ? Colors.white : p.text1,
              fontSize: 15,
              height: 1.35,
            ),
            onSimpleTap: _onTextSimpleTap,
          ),
          _footerMeta(p, onAccent),
        ],
      ),
    );
  }

  void _onTextSimpleTap() {
    if (message.isCall) {
      _callbackFromCallMessage(context);
      return;
    }
    final menu = MessageContextMenuController.instance;
    if (menu.isOpenFor(_bubbleKey)) {
      menu.handleBubbleTap(_bubbleKey);
      return;
    }
    _showActions();
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
      onTap: () => _openDocumentIfDownloaded(context, file),
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

  const _Bubble({
    required this.maxWidth,
    required this.borderRadius,
    required this.color,
    required this.padding,
    required this.child,
    this.liquidGlass = false,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: IntrinsicWidth(child: bubble),
    );
  }
}

/// Текст сообщения: тап открывает меню действий, drag — выделение без
/// системного toolbar/copy popup. ⌘C / Ctrl+C при выделении работают.
class _MessageBodyText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback onSimpleTap;

  const _MessageBodyText({
    required this.text,
    required this.style,
    required this.onSimpleTap,
  });

  @override
  State<_MessageBodyText> createState() => _MessageBodyTextState();
}

class _MessageBodyTextState extends State<_MessageBodyText> {
  static const _dragSlop = 6.0;

  Offset? _downGlobal;
  bool _dragged = false;

  void _onPointerDown(PointerDownEvent e) {
    _downGlobal = e.position;
    _dragged = false;
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
    _downGlobal = null;
    _dragged = false;
    // Простой тап (без выделения) — меню как у медиа.
    if (!wasDrag) {
      widget.onSimpleTap();
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _downGlobal = null;
    _dragged = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: SelectableText(
        widget.text,
        style: widget.style,
        // Без системного окна Copy / Look Up / Share при выделении.
        contextMenuBuilder: (context, editableTextState) =>
            const SizedBox.shrink(),
        magnifierConfiguration: TextMagnifierConfiguration.disabled,
      ),
    );
  }
}
