import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../api/message_mapper.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import 'chat_drop_target.dart';
import '../utils/chat_message_search.dart';
import '../utils/chat_session_scroll.dart';
import 'chat_header.dart';
import 'chat_pane_background.dart';
import 'chat_scroll_scope.dart';
import 'chat_search_bar.dart';
import 'chat_search_scope.dart';
import 'date_separator.dart';
import 'message_input.dart';
import 'message_item.dart';

/// Правая панель: открытая переписка.
/// Список reverse:true — последние сообщения сразу у низа, без начального скролла.
class ChatView extends StatefulWidget {
  final DialogsListViewModel dialog;
  final bool showBack;

  const ChatView({
    super.key,
    required this.dialog,
    this.showBack = false,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  ScrollController? _scrollController;
  bool _scrollInitialized = false;
  final Map<String, GlobalKey> _messageKeys = {};
  bool _pendingScrollToBottom = false;
  bool _loadingOlderRequested = false;
  bool _isRestoringScroll = false;
  int? _lastMessageCount;
  String? _lastTailMessageId;
  bool _showScrollToBottom = false;
  bool _scrollingToBottom = false;
  double _lastScrollOffset = 0;
  Timer? _searchDebounce;

  /// Сколько самых новых сообщений уже показаны при первом открытии.
  /// Растёт от 1 вверх без скролла (reverse-список).
  int _initialVisibleTail = 0;
  bool _initialTailRevealDone = false;
  bool _initialTailRevealScheduled = false;
  int _revealGen = 0;

  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<String> _searchMatchIds = const [];
  int _searchMatchIndex = -1;
  bool _searchLoadingMore = false;
  int _searchLoadToken = 0;

  AppState? _appState;

  static const _scrollToBottomThreshold = 80.0;

  ScrollController get _sc {
    assert(_scrollController != null, 'ScrollController not initialized');
    return _scrollController!;
  }

  void _ensureScrollController(AppState state) {
    if (_scrollInitialized) return;
    _scrollInitialized = true;
    _appState = state;

    final dlgId = widget.dialog.id;
    final saved = ChatSessionScroll.pixels(dlgId);
    final revisited = ChatSessionScroll.wasOpened(dlgId);

    // reverse: true — низ = 0. Повторный вход: initialScrollOffset без jumpTo.
    _scrollController = ScrollController(
      initialScrollOffset: saved ?? 0,
    );
    _lastScrollOffset = saved ?? 0;
    _scrollController!.addListener(_onScroll);
    _scrollController!.addListener(_trackScrollPosition);

    if (revisited) {
      _initialTailRevealDone = true;
      _initialVisibleTail = 1 << 20;
    }
  }

  void _disposeScrollController() {
    if (!_scrollInitialized) return;
    final dlgId = widget.dialog.id;
    if (_sc.hasClients) {
      ChatSessionScroll.save(dlgId, _sc.position.pixels);
    } else {
      ChatSessionScroll.save(dlgId, _lastScrollOffset);
    }
    _scrollController!.removeListener(_onScroll);
    _scrollController!.removeListener(_trackScrollPosition);
    _scrollController!.dispose();
    _scrollController = null;
    _scrollInitialized = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    _appState = state;
    _ensureScrollController(state);
  }

  void _jumpToListEnd() {
    if (!_sc.hasClients) return;
    if (_sc.position.pixels <= 0.5) return;
    _isRestoringScroll = true;
    _sc.jumpTo(0);
    _isRestoringScroll = false;
  }

  void _resetInitialTailReveal() {
    _revealGen++;
    _initialVisibleTail = 0;
    _initialTailRevealDone = false;
    _initialTailRevealScheduled = false;
  }

  /// Показываем хвост снизу вверх без jumpTo/скролла — только после
  /// готовности первой страницы (~100) в AppState.
  void _ensureInitialTailReveal(int totalMessages) {
    if (_initialTailRevealDone) return;
    if (totalMessages <= 0) {
      _initialTailRevealDone = true;
      _initialVisibleTail = 0;
      ChatSessionScroll.markOpened(widget.dialog.id);
      return;
    }
    // Первый кадр после загрузки: только самое последнее у низа.
    if (_initialVisibleTail <= 0) {
      _initialVisibleTail = 1;
    }
    if (_initialVisibleTail >= totalMessages) {
      _initialTailRevealDone = true;
      _initialVisibleTail = totalMessages;
      _initialTailRevealScheduled = false;
      ChatSessionScroll.markOpened(widget.dialog.id);
      return;
    }
    if (_initialTailRevealScheduled) return;
    _initialTailRevealScheduled = true;
    final gen = ++_revealGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialTailRevealScheduled = false;
      if (!mounted || _initialTailRevealDone || gen != _revealGen) return;
      final total = _resolveDialog(
        _appState ?? context.read<AppState>(),
      ).messages.length;
      if (total <= 0) {
        setState(() {
          _initialTailRevealDone = true;
          _initialVisibleTail = 0;
        });
        ChatSessionScroll.markOpened(widget.dialog.id);
        return;
      }
      final int next;
      if (_initialVisibleTail < 12) {
        next = (_initialVisibleTail + 1).clamp(1, total);
      } else {
        next = total;
      }
      setState(() {
        _initialVisibleTail = next;
        if (next >= total) {
          _initialTailRevealDone = true;
        }
      });
      if (next >= total) {
        ChatSessionScroll.markOpened(widget.dialog.id);
      } else {
        _ensureInitialTailReveal(total);
      }
    });
  }

  List<MessageViewModel> _messagesForDisplay(List<MessageViewModel> messages) {
    if (_initialTailRevealDone || messages.isEmpty) return messages;
    final n = _initialVisibleTail.clamp(0, messages.length);
    if (n <= 0) return const [];
    if (n >= messages.length) return messages;
    return messages.sublist(messages.length - n);
  }

  DialogsListViewModel _resolveDialog(AppState state) {
    final dlgId = widget.dialog.id;
    if (dlgId == null) return widget.dialog;
    for (final d in state.dialogs) {
      if (d.id == dlgId) return d;
    }
    return widget.dialog;
  }

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialog.id != widget.dialog.id) {
      _disposeScrollController();
      _loadingOlderRequested = false;
      _lastMessageCount = null;
      _lastTailMessageId = null;
      _pendingScrollToBottom = false;
      _showScrollToBottom = false;
      _messageKeys.clear();
      _resetInitialTailReveal();
      final state = context.read<AppState>();
      _ensureScrollController(state);
      return;
    }

    final state = context.read<AppState>();
    final oldDialog = _resolveDialogFrom(state, oldWidget.dialog);
    final newDialog = _resolveDialogFrom(state, widget.dialog);

    final oldLen = oldDialog.messages.length;
    final newLen = newDialog.messages.length;
    if (newLen > oldLen) {
      final tailChanged = oldLen == 0 ||
          oldDialog.messages.last.id != newDialog.messages.last.id;
      _markFollowTail(
        newDialog.messages,
        newOutgoing: tailChanged && newDialog.messages.last.my,
      );
      return;
    }

    if (newLen > 0 &&
        oldLen > 0 &&
        oldDialog.messages.last.id != newDialog.messages.last.id) {
      _markFollowTail(
        newDialog.messages,
        newOutgoing: newDialog.messages.last.my,
      );
    }
  }

  DialogsListViewModel _resolveDialogFrom(
    AppState state,
    DialogsListViewModel fallback,
  ) {
    final dlgId = fallback.id;
    if (dlgId == null) return fallback;
    for (final d in state.dialogs) {
      if (d.id == dlgId) return d;
    }
    return fallback;
  }

  @override
  void deactivate() {
    if (_scrollInitialized && _sc.hasClients) {
      ChatSessionScroll.save(widget.dialog.id, _sc.position.pixels);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _revealGen++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _disposeScrollController();
    super.dispose();
  }

  bool _isChatActive(AppState state) {
    if (state.navTab != BottomNavTab.chats) return false;
    final dlgId = widget.dialog.id;
    if (dlgId == null) return false;
    return AppState.dlgIdsEqual(state.selectedId, dlgId);
  }

  void _trackScrollPosition() {
    if (_isRestoringScroll || !_sc.hasClients) return;
    if (_pendingScrollToBottom && _sc.offset > 160) {
      _pendingScrollToBottom = false;
    }
    _updateScrollToBottomButton();
  }

  void _updateScrollToBottomButton() {
    if (!_sc.hasClients ||
        _isRestoringScroll ||
        _scrollingToBottom) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }

    // reverse: расстояние до низа = pixels.
    final pixels = _sc.position.pixels;
    final distance = pixels;
    final delta = pixels - _lastScrollOffset;
    _lastScrollOffset = pixels;

    final bool show;
    if (distance <= _scrollToBottomThreshold) {
      show = false;
    } else if (delta < -2) {
      show = true;
    } else if (delta > 2) {
      show = false;
    } else {
      show = _showScrollToBottom;
    }

    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  Future<void> _animateScrollToBottom() async {
    if (!_sc.hasClients || !mounted || _scrollingToBottom) return;

    setState(() {
      _showScrollToBottom = false;
      _scrollingToBottom = true;
    });
    _isRestoringScroll = true;

    try {
      final state = _appState;
      final messages = state != null ? _resolveDialog(state).messages : const [];
      if (messages.isEmpty) return;

      final lastRef = _messageStableKey(messages.last);

      for (var i = 0; i < 8; i++) {
        if (!mounted || !_sc.hasClients) return;
        final ctx = _messageKeys[lastRef]?.currentContext;
        if (ctx != null) break;
        if (_sc.position.pixels > 1) {
          _sc.jumpTo(0);
        }
        await WidgetsBinding.instance.endOfFrame;
      }

      final lastContext = _messageKeys[lastRef]?.currentContext;
      if (lastContext != null && lastContext.mounted) {
        await Scrollable.ensureVisible(
          lastContext,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
          alignment: 1.0,
        );
      }

      for (var attempt = 0; attempt < 6; attempt++) {
        if (!mounted || !_sc.hasClients) return;
        if (_sc.position.pixels.abs() < 2) break;

        await _sc.animateTo(
          0,
          duration: Duration(milliseconds: 280 + attempt * 40),
          curve: Curves.easeInOutCubic,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _finishScrollToBottom();
    }
  }

  void _finishScrollToBottom() {
    if (!mounted) return;
    _isRestoringScroll = false;
    _scrollingToBottom = false;
    _pendingScrollToBottom = false;
    if (_sc.hasClients) {
      _lastScrollOffset = _sc.position.pixels;
    }
    _updateScrollToBottomButton();
  }

  void _scrollToBottom() {
    _jumpToListEnd();
  }

  bool _shouldFollowTail(
    List<MessageViewModel> messages, {
    bool newOutgoing = false,
  }) {
    if (messages.isEmpty) return false;
    if (_isRestoringScroll) return false;

    final state = _appState;
    if (state == null || !_isChatActive(state)) return false;

    if (newOutgoing) return true;

    if (!_sc.hasClients) return false;

    // reverse: у низа offset ≈ 0.
    return _sc.offset <= 160;
  }

  void _markFollowTail(
    List<MessageViewModel> messages, {
    bool newOutgoing = false,
  }) {
    if (!_shouldFollowTail(messages, newOutgoing: newOutgoing)) return;
    _pendingScrollToBottom = true;
  }

  int _entryIndexForMessage(List<MessageViewModel> messages, String messageRef) {
    final entries = _entries(messages);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is _MessageEntry && _messageMatchesRef(entry.message, messageRef)) {
        return i;
      }
    }
    return -1;
  }

  /// Стабильный ключ виджета: hash не меняется после эха сервера (id меняется).
  String _messageStableKey(MessageViewModel message) {
    final hash = message.hash.trim();
    if (hash.isNotEmpty) return hash;
    return message.id.trim();
  }

  bool _messageMatchesRef(MessageViewModel message, String ref) {
    final key = ref.trim();
    if (key.isEmpty) return false;
    if (message.id.trim() == key) return true;
    if (message.hash.trim() == key) return true;
    return false;
  }

  MessageViewModel? _findMessageByRef(
    List<MessageViewModel> messages,
    String ref,
  ) {
    for (final message in messages) {
      if (_messageMatchesRef(message, ref)) return message;
    }
    return null;
  }

  void _pruneMessageKeys(Set<String> activeKeys) {
    _messageKeys.removeWhere((id, _) => !activeKeys.contains(id));
  }

  GlobalKey _keyForMessage(MessageViewModel message) {
    return _messageKeys.putIfAbsent(_messageStableKey(message), GlobalKey.new);
  }

  Future<void> _scrollToMessage(String messageId) async {
    _pendingScrollToBottom = false;
    await _scrollToMessageInternal(
      messageId,
      animate: true,
      alignment: 0.35,
    );
  }

  void _openChatSearch() {
    if (_searchOpen) {
      _searchFocusNode.requestFocus();
      return;
    }
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _closeChatSearch() {
    if (!_searchOpen) return;
    _searchDebounce?.cancel();
    _searchLoadToken++;
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
      _searchMatchIds = const [];
      _searchMatchIndex = -1;
      _searchLoadingMore = false;
    });
  }

  void _onSearchQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _runChatSearch(value);
    });
  }

  Future<void> _runChatSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchLoadToken++;
      if (!mounted) return;
      setState(() {
        _searchQuery = '';
        _searchMatchIds = const [];
        _searchMatchIndex = -1;
        _searchLoadingMore = false;
      });
      return;
    }

    final token = ++_searchLoadToken;
    final dlgId = widget.dialog.id?.trim();
    if (dlgId == null) return;

    final state = context.read<AppState>();
    var messages = _resolveDialog(state).messages;
    var matches = ChatMessageSearch.matchIds(
      messages,
      trimmed,
      stableId: _messageStableKey,
    );

    if (!mounted || token != _searchLoadToken) return;
    setState(() {
      _searchQuery = trimmed;
      _searchMatchIds = matches;
      _searchMatchIndex = matches.isEmpty ? -1 : matches.length - 1;
    });

    if (matches.isNotEmpty) {
      await _scrollToMessage(matches.last);
    }

    if (!state.hasMoreMessages(dlgId)) return;

    if (!mounted || token != _searchLoadToken) return;
    setState(() => _searchLoadingMore = true);

    var attempts = 0;
    while (state.hasMoreMessages(dlgId) &&
        attempts < 24 &&
        mounted &&
        token == _searchLoadToken &&
        _searchQuery == trimmed) {
      await state.loadOlderMessages(dlgId);
      if (!mounted || token != _searchLoadToken) return;

      messages = _resolveDialog(state).messages;
      final updated = ChatMessageSearch.matchIds(
        messages,
        trimmed,
        stableId: _messageStableKey,
      );
      if (updated.length != matches.length) {
        matches = updated;
        setState(() {
          _searchMatchIds = matches;
          if (_searchMatchIndex < 0 && matches.isNotEmpty) {
            _searchMatchIndex = matches.length - 1;
          } else if (_searchMatchIndex >= matches.length) {
            _searchMatchIndex = matches.length - 1;
          }
        });
      }
      attempts++;
    }

    if (!mounted || token != _searchLoadToken) return;
    setState(() => _searchLoadingMore = false);
  }

  Future<void> _goToSearchMatch(int delta) async {
    if (_searchMatchIds.isEmpty) return;

    var index = _searchMatchIndex;
    if (index < 0) index = _searchMatchIds.length - 1;

    final dlgId = widget.dialog.id?.trim();
    final state = context.read<AppState>();

    while (mounted) {
      index += delta;
      if (index < 0) {
        if (dlgId != null &&
            state.hasMoreMessages(dlgId) &&
            _searchQuery.isNotEmpty) {
          setState(() => _searchLoadingMore = true);
          await state.loadOlderMessages(dlgId);
          if (!mounted) return;
          final matches = ChatMessageSearch.matchIds(
            _resolveDialog(state).messages,
            _searchQuery,
            stableId: _messageStableKey,
          );
          setState(() {
            _searchMatchIds = matches;
            _searchLoadingMore = false;
            _searchMatchIndex =
                matches.isEmpty ? -1 : matches.length - 1;
          });
          if (matches.isEmpty) return;
          await _scrollToMessage(matches.last);
          return;
        }
        return;
      }
      if (index >= _searchMatchIds.length) return;

      final id = _searchMatchIds[index];
      setState(() => _searchMatchIndex = index);
      await _scrollToMessage(id);
      return;
    }
  }

  void _handleChatSearchRequest(AppState state) {
    final requestId = state.chatSearchRequestDlgId;
    if (requestId == null) return;
    final dlgId = widget.dialog.id?.trim();
    if (dlgId == null || !AppState.dlgIdsEqual(requestId, dlgId)) return;
    // Без notify во время build — иначе Provider падает.
    state.clearChatSearchRequest(notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openChatSearch();
    });
  }

  void _handleOpenMessageRequest(AppState state) {
    final requestDlgId = state.openMessageRequestDlgId;
    final messageId = state.openMessageRequestId;
    if (requestDlgId == null || messageId == null) return;
    final dlgId = widget.dialog.id?.trim();
    if (dlgId == null || !AppState.dlgIdsEqual(requestDlgId, dlgId)) return;
    state.clearOpenMessageRequest(notify: false);
    final targetId = messageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToMessage(targetId));
    });
  }

  String? _searchHighlightFor(MessageViewModel message) {
    if (_searchQuery.isEmpty) return null;
    final key = _messageStableKey(message);
    if (!_searchMatchIds.contains(key)) return null;
    return _searchQuery;
  }

  bool _searchIsCurrentMatch(MessageViewModel message) {
    if (_searchMatchIndex < 0 || _searchMatchIndex >= _searchMatchIds.length) {
      return false;
    }
    return _searchMatchIds[_searchMatchIndex] == _messageStableKey(message);
  }

  Future<bool> _scrollToMessageInternal(
    String messageRef, {
    required bool animate,
    double alignment = 0,
    double offsetFromTop = 0,
  }) async {
    final id = messageRef.trim();
    if (id.isEmpty) return false;

    final dlgId = widget.dialog.id;
    if (dlgId == null) return false;

    List<MessageViewModel> currentMessages() {
      if (!mounted) return const [];
      final state = _appState ?? context.read<AppState>();
      return _resolveDialog(state).messages;
    }

    var entryIndex = _entryIndexForMessage(currentMessages(), id);

    if (entryIndex < 0) {
      final state = _appState ?? context.read<AppState>();
      var loadAttempts = 0;
      while (entryIndex < 0 &&
          loadAttempts < 20 &&
          state.hasMoreMessages(dlgId)) {
        await state.loadOlderMessages(dlgId);
        if (!mounted) return false;
        entryIndex = _entryIndexForMessage(currentMessages(), id);
        loadAttempts++;
      }
      if (entryIndex < 0) return false;
    }

    const maxAttempts = 32;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted || !_sc.hasClients) return false;

      final target = _findMessageByRef(currentMessages(), id);
      final stableKey =
          target != null ? _messageStableKey(target) : id.trim();

      final key = _messageKeys[stableKey];
      final targetContext = key?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        if (animate) {
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: alignment,
          );
        } else {
          final ro = targetContext.findRenderObject();
          if (ro is RenderBox && ro.hasSize) {
            final itemTop = RenderAbstractViewport.of(ro)
                .getOffsetToReveal(ro, 0.0)
                .offset;
            final jumpTo = (itemTop + offsetFromTop)
                .clamp(0.0, _sc.position.maxScrollExtent);
            _isRestoringScroll = true;
            _sc.jumpTo(jumpTo);
            _isRestoringScroll = false;
          } else {
            await Scrollable.ensureVisible(
              targetContext,
              duration: Duration.zero,
              alignment: 0,
            );
            if (offsetFromTop != 0 && _sc.hasClients) {
              final jumpTo = (_sc.offset + offsetFromTop)
                  .clamp(0.0, _sc.position.maxScrollExtent);
              _isRestoringScroll = true;
              _sc.jumpTo(jumpTo);
              _isRestoringScroll = false;
            }
          }
        }
        if (!mounted) return false;
        return true;
      }

      final messages = currentMessages();
      final entriesCount = _entries(messages).length;
      if (entriesCount <= 0) return false;

      final pos = _sc.position;
      final fraction = (entryIndex + 0.5) / entriesCount;
      final jumpTo =
          (fraction * pos.maxScrollExtent).clamp(0.0, pos.maxScrollExtent);
      _isRestoringScroll = true;
      _sc.jumpTo(jumpTo);
      _isRestoringScroll = false;
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    final pos = _sc.position;
    // reverse: старые сообщения у maxScrollExtent (вверх по истории).
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - 120) return;

    final dlgId = widget.dialog.id;
    if (dlgId == null) return;

    final state = context.read<AppState>();
    if (!state.hasMoreMessages(dlgId)) return;
    if (state.messagesLoadingOlder || _loadingOlderRequested) return;

    _loadingOlderRequested = true;
    _loadOlderWithAnchor(dlgId);
  }

  Future<void> _loadOlderWithAnchor(String dlgId) async {
    await context.read<AppState>().loadOlderMessages(dlgId);
    if (!mounted) return;
    _loadingOlderRequested = false;
    // reverse: рост истории у «верха», позиция от низа сохраняется сама.
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _ensureScrollController(state);
    final p = context.palette;

    final dialog = _resolveDialog(state);
    final messages = dialog.messages;

    final prevCount = _lastMessageCount;
    _lastMessageCount = messages.length;
    final tailId = messages.isNotEmpty ? messages.last.id : null;
    final tailChanged = tailId != null && tailId != _lastTailMessageId;
    _lastTailMessageId = tailId;

    if (prevCount != null &&
        (messages.length > prevCount ||
            (messages.length == prevCount && tailChanged))) {
      _markFollowTail(
        messages,
        newOutgoing: messages.isNotEmpty && messages.last.my && tailChanged,
      );
    }

    final dlgId = dialog.id;
    final isBlankChat = DialogsListViewModel.isPlaceholderDlgId(dlgId) ||
        dialog.isNewContactWithoutDialog;
    final historyReady =
        isBlankChat || state.isDialogHistoryReady(dlgId);

    // Ждём первую страницу (~100), кэш до этого не показываем.
    final loading = !historyReady;
    final loadingOlder = state.messagesLoadingOlder;
    final error = state.messagesError;

    if (historyReady && messages.isNotEmpty) {
      _ensureInitialTailReveal(messages.length);
    } else if (historyReady && messages.isEmpty && !_initialTailRevealDone) {
      _initialTailRevealDone = true;
    }

    final displayMessages =
        historyReady ? _messagesForDisplay(messages) : const <MessageViewModel>[];
    final entries = _entries(displayMessages);
    final deferMedia = !_initialTailRevealDone;

    _pruneMessageKeys(displayMessages.map(_messageStableKey).toSet());

    // Follow-tail только после полной отрисовки хвоста — без jump на старте.
    if (_pendingScrollToBottom &&
        _initialTailRevealDone &&
        messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
        _pendingScrollToBottom = false;
      });
    }

    _handleChatSearchRequest(state);
    _handleOpenMessageRequest(state);

    return ChatPaneBackground(
      child: ChatScrollScope(
        scrollToMessage: _scrollToMessage,
        child: ChatSearchScope(
        openSearch: _openChatSearch,
        closeSearch: _closeChatSearch,
        isOpen: _searchOpen,
        child: ChatDropTarget(
        child: Column(
        children: [
          if (_searchOpen)
            ChatSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              loadingMore: _searchLoadingMore,
              matchCount: _searchMatchIds.length,
              matchIndex: _searchMatchIndex,
              onClose: _closeChatSearch,
              onQueryChanged: _onSearchQueryChanged,
              onPrevious: () => _goToSearchMatch(-1),
              onNext: () => _goToSearchMatch(1),
            )
          else
            ChatHeader(
              dialog: dialog,
              showBack: widget.showBack,
              onSearch: _openChatSearch,
            ),
          if (error != null)
            Material(
              color: Colors.redAccent.withValues(alpha: 0.12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(color: p.text1, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => state.loadMessages(
                        dialog.id!,
                        force: true,
                      ),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: p.purple),
                        const SizedBox(height: 12),
                        Text(
                          'Загрузка сообщений…',
                          style: TextStyle(color: p.text2, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : messages.isEmpty
                    ? _EmptyConversation(palette: p)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) =>
                                AttachmentSelection.clearIfOutside(),
                            child: ListView.builder(
                              controller: _sc,
                              reverse: true,
                              primary: false,
                              physics: _initialTailRevealDone
                                  ? const AlwaysScrollableScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              key: ValueKey<String>(
                                'msg_list_${dialog.id ?? ''}',
                              ),
                              scrollCacheExtent:
                                  const ScrollCacheExtent.pixels(2400),
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              itemCount: entries.length +
                                  (loadingOlder && _initialTailRevealDone
                                      ? 1
                                      : 0),
                              itemBuilder: (context, index) {
                                if (loadingOlder &&
                                    _initialTailRevealDone &&
                                    index == entries.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: p.purple,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final entry =
                                    entries[entries.length - 1 - index];
                                return switch (entry) {
                                  _DateEntry(:final label) =>
                                    DateSeparator(label: label),
                                  _MessageEntry(:final message) =>
                                    MessageItem(
                                      key: _keyForMessage(message),
                                      message: message,
                                      isGroupChat: dialog.isGrp,
                                      deferMediaPreview: deferMedia,
                                      searchQuery:
                                          _searchHighlightFor(message),
                                      searchHighlightCurrent:
                                          _searchIsCurrentMatch(message),
                                    ),
                                };
                              },
                            ),
                          ),
                          _ScrollToBottomButton(
                            visible: _showScrollToBottom,
                            onTap: _animateScrollToBottom,
                          ),
                        ],
                      ),
          ),
          const MessageInput(),
        ],
      ),
      ),
      ),
      ),
    );
  }

  List<_ChatEntry> _entries(List<MessageViewModel> messages) {
    final result = <_ChatEntry>[];
    for (var i = 0; i < messages.length; i++) {
      if (_shouldShowDateSeparator(messages, i)) {
        result.add(_DateEntry(MessageMapper.dateLabel(messages[i].dttmcr)));
      }
      result.add(_MessageEntry(messages[i]));
    }
    return result;
  }

  bool _shouldShowDateSeparator(List<MessageViewModel> messages, int index) {
    if (index == 0) return true;
    final prev = messages[index - 1].dttmcr;
    final curr = messages[index].dttmcr;
    if (prev.isEmpty || curr.isEmpty) return false;
    try {
      final a = DateTime.parse(prev).toLocal();
      final b = DateTime.parse(curr).toLocal();
      return a.year != b.year || a.month != b.month || a.day != b.day;
    } catch (_) {
      return false;
    }
  }
}

sealed class _ChatEntry {
  const _ChatEntry();
}

class _DateEntry extends _ChatEntry {
  final String label;
  const _DateEntry(this.label);
}

class _MessageEntry extends _ChatEntry {
  final MessageViewModel message;
  const _MessageEntry(this.message);
}

class _EmptyConversation extends StatelessWidget {
  final ForumPalette palette;
  const _EmptyConversation({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Сообщений пока нет',
        style: TextStyle(color: palette.text2, fontSize: 15),
      ),
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const _ScrollToBottomButton({
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Positioned(
      right: 16,
      bottom: 12,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.4),
          duration: const Duration(milliseconds: 300),
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: Material(
              color: p.bg2,
              elevation: visible ? 3 : 0,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: p.purple,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
