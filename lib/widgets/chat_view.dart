import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/chat_scroll_anchor.dart';

import '../api/message_mapper.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'cached_forum_image.dart';
import 'chat_header.dart';
import 'chat_scroll_scope.dart';
import 'date_separator.dart';
import 'message_input.dart';
import 'message_item.dart';

/// Правая панель: открытая переписка.
class ChatView extends StatefulWidget {
  final DialogsListViewModel dialog;
  final bool showBack;

  const ChatView({super.key, required this.dialog, this.showBack = false});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  ScrollController? _scrollController;
  bool _scrollInitialized = false;
  final Map<String, GlobalKey> _messageKeys = {};
  bool _pendingScrollToBottom = false;
  bool _pendingRestoreScroll = true;
  bool _initialScrollSettled = false;
  bool _scrollAnchorPreloadDone = false;
  bool _loadingOlderRequested = false;
  bool _isRestoringScroll = false;
  bool _scrollAnchorPreloadStarted = false;
  bool _scrollControllerReady = false;
  bool _restoreScheduled = false;
  int? _lastMessageCount;
  String? _lastTailMessageId;

  double _cachedScrollPixels = 0;
  double _cachedScrollMaxExtent = 0;
  String? _lastAnchorMessageRef;
  double _lastOffsetFromTop = 0;
  bool _messageRestoreInFlight = false;
  bool _wasChatActive = false;
  bool _showScrollToBottom = false;
  bool _scrollingToBottom = false;
  double _lastScrollOffset = 0;
  Timer? _saveDebounce;

  AppState? _appState;
  String? _registeredDlgId;

  static const _maxRestoreAttempts = 24;
  static const _scrollMatchTolerance = 20.0;
  static const _scrollToBottomThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _startScrollAnchorPreload();
  }

  ScrollController get _sc {
    assert(_scrollController != null, 'ScrollController not initialized');
    return _scrollController!;
  }

  void _ensureScrollController(AppState state) {
    if (_scrollInitialized) return;
    _scrollInitialized = true;

    final dlgId = widget.dialog.id?.trim();
    final anchor = dlgId != null ? state.chatScrollAnchor(dlgId) : null;
    final messages = _resolveDialog(state).messages;
    final entryCount = messages.isEmpty ? 0 : _entries(messages).length;
    final hasAnchor = anchor != null && anchor.isUsable;

    var initial = 0.0;
    if (hasAnchor && entryCount > 0) {
      initial = anchor.estimatedOffsetForItemCount(entryCount);
    }

    _scrollController = ScrollController(
      initialScrollOffset: initial,
    );
    _lastScrollOffset = initial;
    _scrollController!.addListener(_onScroll);
    _scrollController!.addListener(_trackScrollPosition);

    if (hasAnchor) {
      _primeScrollFromAnchor(anchor);
      _pendingRestoreScroll = true;
      _pendingScrollToBottom = false;
    } else {
      _pendingRestoreScroll = false;
      _pendingScrollToBottom = entryCount > 0;
    }
  }

  void _disposeScrollController() {
    if (!_scrollInitialized) return;
    _scrollController!.removeListener(_onScroll);
    _scrollController!.removeListener(_trackScrollPosition);
    _scrollController!.dispose();
    _scrollController = null;
    _scrollInitialized = false;
    _scrollControllerReady = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    _ensureScrollController(state);
    if (!identical(_appState, state)) {
      _unregisterScrollSaver();
      _appState = state;
      _registerScrollSaver();
    }
  }

  void _registerScrollSaver() {
    final dlgId = widget.dialog.id?.trim();
    final state = _appState;
    if (dlgId == null || dlgId.isEmpty || state == null) return;
    _registeredDlgId = dlgId;
    state.registerChatScrollSaver(dlgId, _commitScrollPosition);
    _primeScrollFromAnchor(state.chatScrollAnchor(dlgId));
  }

  /// Если якорь уже в памяти — сразу выставляем offset до первого кадра.
  void _primeScrollFromAnchor(ChatScrollAnchor? anchor) {
    if (anchor == null || _scrollControllerReady) return;
    _scrollControllerReady = true;
    if (anchor.hasMessageRef) {
      _lastAnchorMessageRef = anchor.messageRef;
      _lastOffsetFromTop = anchor.offsetFromTop;
      _cachedScrollPixels = anchor.pixels;
      _cachedScrollMaxExtent = anchor.maxExtent;
      return;
    }
    if (anchor.pixels > 0 || anchor.maxExtent > 0) {
      _cachedScrollPixels = anchor.pixels;
      _cachedScrollMaxExtent = anchor.maxExtent;
      _pendingRestoreScroll = true;
    }
  }

  void _unregisterScrollSaver() {
    final dlgId = _registeredDlgId;
    final state = _appState;
    if (dlgId == null || state == null) return;
    state.unregisterChatScrollSaver(dlgId);
    _registeredDlgId = null;
  }

  void _startScrollAnchorPreload() {
    final dlgId = widget.dialog.id;
    if (dlgId == null || _scrollAnchorPreloadStarted) return;
    _scrollAnchorPreloadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = _appState ?? (mounted ? context.read<AppState>() : null);
      if (state == null) return;
      await state.preloadChatScrollAnchor(dlgId);
      if (!mounted) return;
      _scrollAnchorPreloadDone = true;
      final anchor = state.chatScrollAnchor(dlgId);
      if (anchor?.isUsable == true) {
        if (anchor!.hasMessageRef) {
          _lastAnchorMessageRef = anchor.messageRef;
          _lastOffsetFromTop = anchor.offsetFromTop;
        } else {
          _cachedScrollPixels = anchor.pixels;
          _cachedScrollMaxExtent = anchor.maxExtent;
        }
        if (!_initialScrollSettled) {
          _pendingRestoreScroll = true;
          _pendingScrollToBottom = false;
        }
      } else if (_pendingRestoreScroll && anchor == null) {
        _pendingRestoreScroll = false;
        _pendingScrollToBottom = true;
      }
      if (mounted) setState(() {});
    });
  }

  void _completeInitialScroll() {
    if (_initialScrollSettled) return;
    _initialScrollSettled = true;
    _pendingRestoreScroll = false;
    _pendingScrollToBottom = false;
    _commitScrollPosition();
    if (mounted) setState(() {});
  }

  void _resetInitialScrollState() {
    _initialScrollSettled = false;
    _scrollAnchorPreloadDone = false;
    _scrollAnchorPreloadStarted = false;
    _pendingRestoreScroll = true;
    _pendingScrollToBottom = false;
    _restoreScheduled = false;
    _showScrollToBottom = false;
    _scrollingToBottom = false;
    _lastScrollOffset = 0;
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
      _commitScrollPosition();
      _unregisterScrollSaver();
      _disposeScrollController();
      _loadingOlderRequested = false;
      _lastMessageCount = null;
      _lastTailMessageId = null;
      _cachedScrollPixels = 0;
      _cachedScrollMaxExtent = 0;
      _messageKeys.clear();
      _resetInitialScrollState();
      _lastAnchorMessageRef = null;
    _lastOffsetFromTop = 0;
    _messageRestoreInFlight = false;
    _scrollControllerReady = false;
      _registerScrollSaver();
      _startScrollAnchorPreload();
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
      _markFollowTail(newDialog.messages);
      return;
    }

    if (newLen > 0 &&
        oldLen > 0 &&
        oldDialog.messages.last.id != newDialog.messages.last.id) {
      _markFollowTail(newDialog.messages);
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
    _commitScrollPosition();
    super.deactivate();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _commitScrollPosition();
    _unregisterScrollSaver();
    _disposeScrollController();
    super.dispose();
  }

  bool _isChatActive(AppState state) {
    if (state.navTab != BottomNavTab.chats) return false;
    final dlgId = widget.dialog.id;
    if (dlgId == null) return false;
    return AppState.dlgIdsEqual(state.selectedId, dlgId);
  }

  bool _scrollOffsetMatchesAnchor(ChatScrollAnchor anchor) {
    if (!_sc.hasClients) return false;
    final pos = _sc.position;

    if (anchor.hasMessageRef) {
      final detected = _detectTopVisibleMessage();
      if (detected != null &&
          detected.$1 == anchor.messageRef &&
          (detected.$2 - anchor.offsetFromTop).abs() < _scrollMatchTolerance) {
        return true;
      }
    }

    if (anchor.pixels <= 0 && anchor.maxExtent <= 0) return false;

    final target = anchor.targetForExtent(pos.maxScrollExtent);
    return (pos.pixels - target).abs() < _scrollMatchTolerance;
  }

  void _trackScrollPosition() {
    if (_isRestoringScroll || !_sc.hasClients) return;
    _cachedScrollPixels = _sc.position.pixels;
    _cachedScrollMaxExtent = _sc.position.maxScrollExtent;
    if (_pendingScrollToBottom &&
        _sc.offset < _sc.position.maxScrollExtent - 160) {
      _pendingScrollToBottom = false;
    }
    final detected = _detectTopVisibleMessage();
    if (detected != null) {
      _lastAnchorMessageRef = detected.$1;
      _lastOffsetFromTop = detected.$2;
    }
    if (!_initialScrollSettled && !_isRestoringScroll) {
      _initialScrollSettled = true;
      _pendingRestoreScroll = false;
      _pendingScrollToBottom = false;
    }
    _updateScrollToBottomButton();
    _scheduleSaveScroll();
  }

  void _updateScrollToBottomButton() {
    if (!_initialScrollSettled ||
        !_sc.hasClients ||
        _isRestoringScroll ||
        _scrollingToBottom) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }

    final pixels = _sc.position.pixels;
    final max = _sc.position.maxScrollExtent;
    final distance = max - pixels;
    final delta = pixels - _lastScrollOffset;
    _lastScrollOffset = pixels;

    final bool show;
    if (distance <= _scrollToBottomThreshold) {
      show = false;
    } else if (delta > 2) {
      // Прокрутка к последним сообщениям — показываем.
      show = true;
    } else if (delta < -2) {
      // Прокрутка вверх по истории — скрываем.
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

      // Дожидаемся построения последнего сообщения (без «пустого» окна).
      for (var i = 0; i < 8; i++) {
        if (!mounted || !_sc.hasClients) return;
        final ctx = _messageKeys[lastRef]?.currentContext;
        if (ctx != null) break;
        final target = _sc.position.maxScrollExtent;
        if ((_sc.position.pixels - target).abs() > 1) {
          _sc.jumpTo(target);
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

      // Догоняем изменившийся maxScrollExtent после подгрузки layout.
      for (var attempt = 0; attempt < 6; attempt++) {
        if (!mounted || !_sc.hasClients) return;
        final target = _sc.position.maxScrollExtent;
        final gap = target - _sc.position.pixels;
        if (gap.abs() < 2) break;

        await _sc.animateTo(
          target,
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
    _commitScrollPosition();
    _updateScrollToBottomButton();
  }

  void _scheduleSaveScroll() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _commitScrollPosition();
    });
  }

  void _commitScrollPosition() {
    final dlgId = widget.dialog.id?.trim();
    final state = _appState;
    if (dlgId == null || dlgId.isEmpty || state == null) return;
    if (_scrollInitialized && _sc.hasClients) {
      _cachedScrollPixels = _sc.position.pixels;
      _cachedScrollMaxExtent = _sc.position.maxScrollExtent;
      final detected = _detectTopVisibleMessage();
      if (detected != null) {
        _lastAnchorMessageRef = detected.$1;
        _lastOffsetFromTop = detected.$2;
      }
    }
    if (_cachedScrollMaxExtent <= 0 && _cachedScrollPixels <= 0) return;
    state.saveChatScrollAnchor(
      dlgId,
      pixels: _cachedScrollPixels,
      maxExtent: _cachedScrollMaxExtent,
      messageRef: _lastAnchorMessageRef,
      offsetFromTop: _lastOffsetFromTop,
    );
  }

  /// (messageRef, offsetFromTop) — насколько viewport ниже верха сообщения.
  (String, double)? _detectTopVisibleMessage() {
    if (!_sc.hasClients) return null;
    final scrollOffset = _sc.offset;

    String? bestRef;
    double bestOffsetFromTop = 0;
    var bestScore = double.infinity;

    for (final entry in _messageKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) continue;

      try {
        final itemTop =
            RenderAbstractViewport.of(ro).getOffsetToReveal(ro, 0.0).offset;
        if (itemTop <= scrollOffset + 4) {
          final score = scrollOffset - itemTop;
          if (score < bestScore) {
            bestScore = score;
            bestRef = entry.key;
            bestOffsetFromTop = score;
          }
        }
      } catch (_) {}
    }

    if (bestRef != null) return (bestRef, bestOffsetFromTop);

    var closestBelow = double.infinity;
    for (final entry in _messageKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) continue;
      try {
        final itemTop =
            RenderAbstractViewport.of(ro).getOffsetToReveal(ro, 0.0).offset;
        if (itemTop > scrollOffset && itemTop - scrollOffset < closestBelow) {
          closestBelow = itemTop - scrollOffset;
          bestRef = entry.key;
          bestOffsetFromTop = scrollOffset - itemTop;
        }
      } catch (_) {}
    }

    return bestRef != null ? (bestRef, bestOffsetFromTop) : null;
  }

  void _scrollToBottom({int attempt = 0, bool settleInitial = false}) {
    if (!_sc.hasClients) {
      if (settleInitial && attempt + 1 >= 3) {
        _completeInitialScroll();
      }
      return;
    }
    final pos = _sc.position;
    final target = pos.maxScrollExtent;
    _sc.jumpTo(target);

    if (attempt + 1 >= 3) {
      if (settleInitial) _completeInitialScroll();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      final extent = _sc.position.maxScrollExtent;
      if (extent > target + 1 ||
          (target - _sc.position.pixels).abs() > 1) {
        _scrollToBottom(attempt: attempt + 1, settleInitial: settleInitial);
      } else if (settleInitial) {
        _completeInitialScroll();
      }
    });
  }

  bool _shouldFollowTail(List<MessageViewModel> messages) {
    if (messages.isEmpty) return false;

    final state = _appState;
    if (state == null || !_isChatActive(state)) return false;

    // Исходящее сообщение — всегда прокручиваем к последнему.
    if (messages.last.my) return true;

    if (!_initialScrollSettled) return false;
    if (!_sc.hasClients) return false;

    return _sc.offset >= _sc.position.maxScrollExtent - 160;
  }

  void _markFollowTail(List<MessageViewModel> messages) {
    if (!_shouldFollowTail(messages)) return;
    _pendingScrollToBottom = true;
    _pendingRestoreScroll = false;
  }

  void _onChatActiveChanged(bool isActive) {
    if (isActive) {
      if (!_initialScrollSettled) return;
      // ChatView остаётся в IndexedStack — ScrollController уже на месте.
      if (_sc.hasClients &&
          _sc.offset > _scrollMatchTolerance) {
        _commitScrollPosition();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (_sc.hasClients &&
            _sc.offset > _scrollMatchTolerance) {
          _commitScrollPosition();
          return;
        }
        _ensureScrollPosition();
      });
      return;
    }
    _saveDebounce?.cancel();
    _initialScrollSettled = true;
    _pendingRestoreScroll = false;
    _pendingScrollToBottom = false;
    if (_sc.hasClients) {
      _cachedScrollPixels = _sc.position.pixels;
      _cachedScrollMaxExtent = _sc.position.maxScrollExtent;
    }
    _commitScrollPosition();
  }

  Future<void> _ensureScrollPosition() async {
    if (!_initialScrollSettled || _pendingRestoreScroll) return;
    final dlgId = widget.dialog.id;
    final state = _appState;
    if (dlgId == null || state == null) return;
    if (!_isChatActive(state)) return;

    final anchor = state.chatScrollAnchor(dlgId);
    if (anchor == null) return;
    if (!_sc.hasClients) return;
    if (_scrollOffsetMatchesAnchor(anchor)) return;

    if (anchor.hasMessageRef) {
      _isRestoringScroll = true;
      await _scrollToMessageInternal(
        anchor.messageRef!,
        animate: false,
        offsetFromTop: anchor.offsetFromTop,
      );
      _isRestoringScroll = false;
      return;
    }

    final target =
        anchor.targetForExtent(_sc.position.maxScrollExtent);
    if ((_sc.offset - target).abs() > _scrollMatchTolerance) {
      _isRestoringScroll = true;
      _sc.jumpTo(target);
      _isRestoringScroll = false;
      _commitScrollPosition();
    }
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
    _pendingRestoreScroll = false;
    _pendingScrollToBottom = false;
    _initialScrollSettled = true;
    await _scrollToMessageInternal(
      messageId,
      animate: true,
      alignment: 0.35,
    );
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
        _lastAnchorMessageRef = stableKey;
        _lastOffsetFromTop = offsetFromTop;
        _commitScrollPosition();
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

  Future<void> _restoreToMessageAnchor(ChatScrollAnchor anchor) async {
    if (_messageRestoreInFlight) return;
    _messageRestoreInFlight = true;
    try {
      final ok = await _scrollToMessageInternal(
        anchor.messageRef!,
        animate: false,
        offsetFromTop: anchor.offsetFromTop,
      );
      if (!mounted) return;
      if (ok) {
        _completeInitialScroll();
        return;
      }
      _restoreScrollPositionPixels(anchor, attempt: _maxRestoreAttempts - 1);
    } finally {
      _messageRestoreInFlight = false;
    }
  }

  void _restoreScrollPosition({int attempt = 0}) {
    final dlgId = widget.dialog.id;
    if (dlgId == null) {
      _completeInitialScroll();
      return;
    }

    if (!_sc.hasClients) {
      if (attempt < _maxRestoreAttempts) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreScrollPosition(attempt: attempt + 1),
        );
      } else {
        _pendingRestoreScroll = false;
        _pendingScrollToBottom = true;
      }
      return;
    }

    final anchor = _appState?.chatScrollAnchor(dlgId);
    if (anchor == null) {
      if (!_scrollAnchorPreloadDone && attempt < _maxRestoreAttempts) {
        if (!_scrollAnchorPreloadStarted) _startScrollAnchorPreload();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreScrollPosition(attempt: attempt + 1),
        );
      } else {
        _pendingRestoreScroll = false;
        _pendingScrollToBottom = true;
      }
      return;
    }

    if (_scrollOffsetMatchesAnchor(anchor)) {
      _completeInitialScroll();
      return;
    }

    if (anchor.hasMessageRef) {
      if (!_messageRestoreInFlight) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pendingRestoreScroll) {
            _restoreToMessageAnchor(anchor);
          }
        });
      }
      return;
    }

    _restoreScrollPositionPixels(anchor, attempt: attempt);
  }

  void _restoreScrollPositionPixels(
    ChatScrollAnchor anchor, {
    required int attempt,
  }) {
    if (!_sc.hasClients) {
      if (attempt < _maxRestoreAttempts) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreScrollPosition(attempt: attempt + 1),
        );
      } else {
        _pendingRestoreScroll = false;
        _pendingScrollToBottom = true;
      }
      return;
    }

    final pos = _sc.position;
    final target = anchor.targetForExtent(pos.maxScrollExtent);
    if ((pos.pixels - target).abs() < 1) {
      _completeInitialScroll();
      return;
    }
    final extentBefore = pos.maxScrollExtent;

    _isRestoringScroll = true;
    _sc.jumpTo(target);
    _isRestoringScroll = false;

    if (attempt + 1 >= _maxRestoreAttempts) {
      _completeInitialScroll();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      final extentAfter = _sc.position.maxScrollExtent;
      if (extentAfter > extentBefore + 1) {
        _restoreScrollPosition(attempt: attempt + 1);
      } else {
        _completeInitialScroll();
      }
    });
  }

  void _scheduleRestoreScroll() {
    if (_restoreScheduled || !_pendingRestoreScroll) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (mounted && _pendingRestoreScroll) {
        _restoreScrollPosition();
      }
    });
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    if (_sc.position.pixels > 120) return;

    final dlgId = widget.dialog.id;
    if (dlgId == null) return;

    // WS_MSG_LIST.md: подгрузка истории при count >= 70.
    if (widget.dialog.messages.length < 70) return;

    final state = context.read<AppState>();
    if (!state.hasMoreMessages(dlgId)) return;
    if (state.messagesLoadingOlder || _loadingOlderRequested) return;

    _loadingOlderRequested = true;
    _loadOlderWithAnchor(dlgId);
  }

  Future<void> _loadOlderWithAnchor(String dlgId) async {
    double? oldExtent;
    double? oldPixels;
    if (_sc.hasClients) {
      oldExtent = _sc.position.maxScrollExtent;
      oldPixels = _sc.position.pixels;
    }

    await context.read<AppState>().loadOlderMessages(dlgId);

    if (!mounted) return;
    _loadingOlderRequested = false;

    if (oldExtent != null && oldPixels != null && _sc.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_sc.hasClients) return;
        final newExtent = _sc.position.maxScrollExtent;
        final delta = newExtent - oldExtent!;
        if (delta > 0) {
          _isRestoringScroll = true;
          _sc.jumpTo(oldPixels! + delta);
          _isRestoringScroll = false;
          _commitScrollPosition();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _ensureScrollController(state);
    final p = context.palette;

    final dialog = _resolveDialog(state);
    final messages = dialog.messages;
    final isActive = _isChatActive(state);
    if (isActive != _wasChatActive) {
      _wasChatActive = isActive;
      _onChatActiveChanged(isActive);
    }

    final prevCount = _lastMessageCount;
    _lastMessageCount = messages.length;
    final tailId = messages.isNotEmpty ? messages.last.id : null;
    final tailChanged = tailId != null && tailId != _lastTailMessageId;
    _lastTailMessageId = tailId;

    if (prevCount != null &&
        (messages.length > prevCount ||
            (messages.length == prevCount && tailChanged))) {
      _markFollowTail(messages);
    }

    final loading = state.messagesLoading && messages.isEmpty;
    final loadingOlder = state.messagesLoadingOlder;
    final error = state.messagesError;
    final entries = _entries(messages);
    final topPad = loadingOlder ? 1 : 0;

    _pruneMessageKeys(messages.map(_messageStableKey).toSet());

    if (!loading &&
        messages.isNotEmpty &&
        _pendingRestoreScroll &&
        !_initialScrollSettled) {
      _scheduleRestoreScroll();
    } else if (!loading &&
        messages.isNotEmpty &&
        _pendingScrollToBottom &&
        !_pendingRestoreScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(settleInitial: !_initialScrollSettled);
        if (_initialScrollSettled) {
          _pendingScrollToBottom = false;
        }
      });
    } else if (!loading && messages.isEmpty && !_initialScrollSettled) {
      _completeInitialScroll();
    }

    final bgUrl = state.chatBackgroundUrl(isDark: state.isDark);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bgUrl != null)
          Positioned.fill(
            child: CachedForumImage(url: bgUrl, fit: BoxFit.cover),
          )
        else
          ColoredBox(color: p.bg1),
        ChatScrollScope(
        scrollToMessage: _scrollToMessage,
        child: Column(
        children: [
          ChatHeader(dialog: dialog, showBack: widget.showBack),
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
                          Opacity(
                            opacity: _initialScrollSettled ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !_initialScrollSettled,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: ListView.builder(
                                  controller: _sc,
                                  primary: false,
                                  scrollCacheExtent:
                                      const ScrollCacheExtent.pixels(2400),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  itemCount: topPad + entries.length,
                                  itemBuilder: (context, index) {
                                  if (loadingOlder && index == 0) {
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
                                  final entry = entries[index - topPad];
                                  return switch (entry) {
                                    _DateEntry(:final label) =>
                                      DateSeparator(label: label),
                                    _MessageEntry(:final message) =>
                                      MessageItem(
                                        key: _keyForMessage(message),
                                        message: message,
                                        isGroupChat: dialog.isGrp,
                                      ),
                                  };
                                },
                              ),
                            ),
                          ),
                          ),
                          if (!_initialScrollSettled)
                            ColoredBox(color: p.bg1),
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
      ],
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
