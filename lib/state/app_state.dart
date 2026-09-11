import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../calls/call_manager.dart';
import '../calls/call_message_display.dart';
import '../calls/call_models.dart';
import '../api/contacts_service.dart';
import '../api/device_id_service.dart';
import '../api/dialog_mapper.dart';
import '../api/client_msg_hash.dart';
import '../api/avatar_upload.dart';
import '../api/api_config.dart';
import '../api/forum_api_client.dart';
import '../api/file_uploader.dart';
import '../api/forward_mapper.dart';
import '../api/likes_mapper.dart';
import '../api/message_mapper.dart';
import '../api/msg_list_cursors.dart';
import '../api/msg_list_merge.dart';
import '../api/msg_list_request.dart';
import '../api/msg_list_result.dart';
import '../api/outgoing_message_payload.dart';
import '../api/profile_mapper.dart';
import '../api/uploaded_file_info.dart';
import '../models/appearance_settings.dart';
import '../models/auth_models.dart';
import '../models/chat_scroll_anchor.dart';
import '../models/chat_type.dart';
import '../models/device_session.dart';
import '../models/dialog_group.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/dlg_info_member.dart';
import '../models/forum_database.dart';
import '../models/global_search_chat_group.dart';
import '../models/global_search_hit.dart';
import '../models/global_search_scope.dart';
import '../models/telegram_reactions.dart';
import '../models/media_file.dart';
import '../models/message_emoji_model.dart';
import '../models/message_view_model.dart';
import '../models/msg_read_entry.dart';
import '../models/user_profile.dart';
import '../services/appearance_prefs.dart';
import '../services/api_logger.dart';
import '../services/auth_session.dart';
import '../services/dialog_local_prefs.dart';
import '../services/firebase_service.dart';
import '../services/forum_cache.dart';
import '../theme/app_theme.dart';
import '../theme/appearance_resolver.dart';
import '../utils/global_search.dart';
import '../utils/chat_file_dnd.dart';
import '../utils/emoticon_replacer.dart';
import '../utils/folder_list_codec.dart';
import '../utils/media_display_name.dart';
import '../utils/media_preprocessor.dart';
import '../utils/reaction_utils.dart';

/// Статус подключения к серверу.
enum ConnectionStatus {
  idle,
  connecting,
  connected,
  error,
}

/// Вкладки нижней навигации.
enum BottomNavTab { chats, projects, tasks, newLog, profile }

/// Встроенные вкладки фильтра (не папки с сервера).
class BuiltinTab {
  static const all = '__all__';
  static const archive = '__archive__';
  static const ai = '__ai__';
  static const personal = '__personal__';

  static const maxFolderNameLength = 24;

  static bool isBuiltin(String tabId) =>
      tabId == all || tabId == archive || tabId == ai || tabId == personal;

  /// ID для `dlg_grp_sort` (клиентские системные папки).
  static String? sortId(String tabId) {
    if (tabId == ai) return '2';
    if (tabId == personal) return '3';
    if (tabId == all) return null;
    return tabId;
  }
}

/// Глобальное состояние приложения.
class AppState extends ChangeNotifier {
  AppState({ForumApiClient? api}) : _api = api ?? ForumApiClient() {
    _api.onMsgPush = _onMsgPush;
    _api.onMsgListPush = _onMsgListPush;
    _api.onDlgCreatedPush = _onDlgCreatedPush;
    _api.onStatusPush = _onStatusPush;
    _api.onMsgDelPush = _onMsgDelPush;
    _api.onAddLikePush = _onAddLikePush;
    _api.onTypingPush = _onTypingPush;
    _api.onPinMsgPush = _onPinMsgPush;
    _api.onForceLogOut = _onForceLogOut;
    _api.onDisconnected = _scheduleReconnect;
    FirebaseService.instance.bindApiClient(_api);
    FirebaseService.instance.onChatRelatedPush = _onChatRelatedPush;
  }

  final ForumApiClient _api;
  bool _reconnectPending = false;

  /// ID входящих сообщений, для которых уже отправлен `status: 2`.
  final Map<String, Set<String>> _readAckSent = {};

  ForumDatabase _database = ForumDatabase.defaults();
  ForumDatabase get database => _database;

  AppearanceSettings _appearance = const AppearanceSettings();
  AppearanceSettings get appearance => _appearance;

  AppearanceResolver get appearanceResolver =>
      AppearanceResolver(database: _database, settings: _appearance);

  ThemeMode get themeMode => switch (_appearance.theme) {
        AppearanceTheme.system => ThemeMode.system,
        AppearanceTheme.dark => ThemeMode.dark,
        AppearanceTheme.light => ThemeMode.light,
      };

  bool get isDark => switch (_appearance.theme) {
        AppearanceTheme.dark => true,
        AppearanceTheme.light => false,
        AppearanceTheme.system => WidgetsBinding
                .instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
      };

  double get textScaleFactor => _appearance.textScaleFactor;

  ThemeData themeFor(Brightness brightness) =>
      AppTheme.build(brightness, appearanceResolver.paletteFor(brightness));

  ThemeData get lightTheme => themeFor(Brightness.light);
  ThemeData get darkTheme => themeFor(Brightness.dark);

  Color nameColor({required bool isDark, int? colorId}) =>
      appearanceResolver.nameColorFor(isDark: isDark, colorId: colorId);

  List<String> currentUserAvatarHex({required bool isDark}) =>
      appearanceResolver.avatarHexFor(isDark: isDark);

  String? chatBackgroundUrl({required bool isDark}) =>
      appearanceResolver.chatBackgroundUrl(isDark: isDark);

  ConnectionStatus _connectionStatus = ConnectionStatus.idle;
  ConnectionStatus get connectionStatus => _connectionStatus;

  bool _authReady = false;
  bool get authReady => _authReady;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  String? _connectionError;
  String? get connectionError => _connectionError;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  List<DialogsListViewModel> _dialogs = [];
  List<DialogGroup> _groups = [];
  List<DialogGroup> get groups => List.unmodifiable(_groups);

  final Map<String, int> _mutedUntil = {};
  final Set<String> _archivedIds = {};
  Timer? _muteExpiryTimer;

  /// Сообщения / msg_list для dlg_id, которых ещё нет в списке (новая группа).
  final Map<String, List<_PendingUnknownDialogPush>> _pendingUnknownDialogPushes =
      {};
  Future<void>? _unknownDialogRefreshInFlight;
  final Set<String> _unknownDialogRefreshQueued = {};
  final Map<String, int> _unknownDialogRefreshAttempts = {};

  /// Пока сервер не пушит новым участникам карточку группы — периодически
  /// синхронизируем `dlg_list` (как pull-to-refresh в фоне).
  Timer? _dialogsPollTimer;
  Future<void>? _refreshDialogsInFlight;
  static const _dialogsPollInterval = Duration(seconds: 8);

  /// Чат покинут/удалён на сервере — не возвращать из `dlg_list`, пока сервер
  /// ещё отдаёт его (гонка с polling).
  final Set<String> _suppressedDlgIds = {};

  String? _selectedId;
  String _activeTab = BuiltinTab.all;
  String get activeTab => _activeTab;

  String _search = '';
  String? _chatSearchRequestDlgId;
  bool _globalSearchRibbonVisible = false;
  GlobalSearchScope _globalSearchScope = GlobalSearchScope.chats;
  Timer? _globalSearchPreloadDebounce;
  int _globalSearchPreloadToken = 0;
  bool _globalSearchPreloading = false;
  int _globalSearchPreloadDone = 0;
  int _globalSearchPreloadTotal = 0;
  final Map<String, Future<void>> _olderMessageLoadsInFlight = {};
  String? _openMessageRequestDlgId;
  String? _openMessageRequestId;
  String? _activeGlobalSearchHitKey;

  BottomNavTab _navTab = BottomNavTab.chats;
  BottomNavTab get navTab => _navTab;

  bool _messagesLoading = false;
  bool _messagesLoadingOlder = false;
  String? _messagesError;
  final Set<String> _messagesLoadedFor = {};
  final Map<String, bool> _msgHasMore = {};
  final Map<String, Future<void>> _messageLoadsInFlight = {};
  /// Локально скрытые сообщения («удалить у себя» / оптимистичное удаление).
  final Map<String, Set<String>> _deletedMessageIds = {};
  final Map<String, ChatScrollAnchor> _chatScrollAnchors = {};
  final Map<String, void Function()> _chatScrollSavers = {};
  int _loadGeneration = 0;
  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  bool _profileAvatarUploading = false;
  bool get profileAvatarUploading => _profileAvatarUploading;

  String get search => _search;
  String? get chatSearchRequestDlgId => _chatSearchRequestDlgId;
  bool get globalSearchRibbonVisible => _globalSearchRibbonVisible;
  GlobalSearchScope get globalSearchScope => _globalSearchScope;
  bool get globalSearchPreloading => _globalSearchPreloading;
  String? get globalSearchPreloadLabel {
    if (!_globalSearchPreloading) return null;
    if (_globalSearchPreloadTotal <= 0) return 'Загрузка истории…';
    return 'Загрузка истории $_globalSearchPreloadDone/$_globalSearchPreloadTotal…';
  }
  String? get openMessageRequestDlgId => _openMessageRequestDlgId;
  String? get openMessageRequestId => _openMessageRequestId;
  String? get activeGlobalSearchHitKey => _activeGlobalSearchHitKey;
  bool get isLoading => _connectionStatus == ConnectionStatus.connecting;
  bool get messagesLoading => _messagesLoading;
  bool get messagesLoadingOlder => _messagesLoadingOlder;

  /// Режим мультивыбора чатов (кнопка-список в шапке, как leftBar iOS).
  bool _dialogsSelectMode = false;
  final Set<String> _selectedDialogIds = {};

  bool get dialogsSelectMode => _dialogsSelectMode;
  Set<String> get selectedDialogIds => Set.unmodifiable(_selectedDialogIds);
  int get selectedDialogsCount => _selectedDialogIds.length;

  void toggleDialogsSelectMode() {
    if (_dialogsSelectMode) {
      _dialogsSelectMode = false;
      _selectedDialogIds.clear();
    } else {
      _dialogsSelectMode = true;
      _selectedDialogIds.clear();
    }
    notifyListeners();
  }

  void exitDialogsSelectMode() {
    if (!_dialogsSelectMode && _selectedDialogIds.isEmpty) return;
    _dialogsSelectMode = false;
    _selectedDialogIds.clear();
    notifyListeners();
  }

  bool isDialogChecked(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return false;
    if (_selectedDialogIds.contains(dlgId.trim())) return true;
    return _selectedDialogIds.any((id) => _sameDlgId(id, dlgId));
  }

  void toggleDialogChecked(String? dlgId) {
    if (!_dialogsSelectMode) return;
    final key = dlgId?.trim();
    if (key == null || key.isEmpty) return;
    String? existing;
    for (final id in _selectedDialogIds) {
      if (_sameDlgId(id, key)) {
        existing = id;
        break;
      }
    }
    if (existing != null) {
      _selectedDialogIds.remove(existing);
    } else {
      _selectedDialogIds.add(key);
    }
    notifyListeners();
  }

  /// Как iOS: без выбора — прочитать все; с выбором — только отмеченные.
  void markDialogsReadFromSelectMode() {
    final targets = _selectedDialogIds.isEmpty
        ? _dialogs
        : _dialogs.where((d) => isDialogChecked(d.id)).toList();
    for (final dialog in targets) {
      final id = dialog.id?.trim();
      if (id == null || id.isEmpty) continue;
      if (dialog.unread > 0) dialog.unread = 0;
      _sendReadStatus(dialog, id);
    }
    notifyListeners();
  }

  /// Удаление выбранных чатов из локального списка (как UI iOS; серверный dlg_del пока нет).
  void deleteSelectedDialogsFromSelectMode() {
    if (_selectedDialogIds.isEmpty) return;
    final toRemove = _dialogs.where((d) => isDialogChecked(d.id)).toList();
    final wasSelectedOpen =
        _selectedId != null && isDialogChecked(_selectedId);
    for (final dialog in toRemove) {
      final id = dialog.id?.trim();
      if (id == null || id.isEmpty) continue;
      dialog.messages.clear();
      _messagesLoadedFor.removeWhere((x) => _sameDlgId(x, id));
      _flushChatScroll(id);
      _chatScrollSavers.removeWhere((k, _) => _sameDlgId(k, id));
    }
    _dialogs.removeWhere((d) => isDialogChecked(d.id));
    if (wasSelectedOpen) {
      _selectedId = null;
    }
    _selectedDialogIds.clear();
    _dialogsSelectMode = false;
    notifyListeners();
  }

  /// Закрепить / открепить чат (`pin_dlg_add` / `pin_dlg_del`).
  Future<void> setDialogPinned(String dlgId, {required bool pinned}) async {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    final previous = dialog.pin;
    dialog.pin = pinned ? 1 : 0;
    _bumpDialog(dlgId);
    notifyListeners();
    try {
      if (pinned) {
        await _api.sendPinDlgAdd(dlgId);
      } else {
        await _api.sendPinDlgDel(dlgId);
      }
      await refreshDialogs();
    } catch (_) {
      dialog.pin = previous;
      notifyListeners();
    }
  }

  /// Локально пометить чат непрочитанным (бейдж).
  void markDialogUnread(String dlgId) {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    if (dialog.unread < 1) dialog.unread = 1;
    notifyListeners();
  }

  /// Пометить чат прочитанным и отправить `status`.
  void markDialogRead(String dlgId) {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    dialog.unread = 0;
    _sendReadStatus(dialog, dlgId);
    notifyListeners();
  }

  /// Выключить / включить уведомления чата (локально, до серверного mute).
  /// [until] — момент окончания; `null` при [muted] = навсегда.
  void setDialogMuted(
    String dlgId, {
    required bool muted,
    DateTime? until,
  }) {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    dialog.chatMuted = muted;
    final key = _prefsKeyFor(dlgId) ?? dlgId.trim();
    if (!muted) {
      _removePrefKey(_mutedUntil, dlgId);
    } else if (until == null) {
      _mutedUntil[key] = 0;
    } else {
      _mutedUntil[key] = until.millisecondsSinceEpoch;
    }
    _scheduleMuteExpiry();
    unawaited(_saveDialogLocalPrefs());
    notifyListeners();
  }

  bool isDialogArchived(String? dlgId) => _hasPrefId(_archivedIds, dlgId);

  /// Спрятать чат в локальный архив (вкладки «Все» / папки его не показывают).
  void setDialogArchived(String dlgId, {required bool archived}) {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    final key = _prefsKeyFor(dlgId) ?? dlgId.trim();
    if (archived) {
      _archivedIds.add(key);
    } else {
      _removePrefId(_archivedIds, dlgId);
      if (_activeTab == BuiltinTab.archive && _archivedIds.isEmpty) {
        _activeTab = BuiltinTab.all;
      }
    }
    unawaited(_saveDialogLocalPrefs());
    notifyListeners();
  }

  /// Добавить или убрать чат из пользовательской папки.
  Future<void> toggleDialogInFolder({
    required String folderId,
    required String dlgId,
  }) async {
    final group = groupById(folderId);
    if (group == null) return;
    final ids = group.dialogIds.toList();
    final has = ids.any((id) => _sameDlgId(id, dlgId));
    if (has) {
      ids.removeWhere((id) => _sameDlgId(id, dlgId));
    } else {
      ids.add(dlgId);
    }
    await updateFolderDialogs(id: folderId, dialogIds: ids);
  }

  /// Очистить историю чата: `msg_del` по известным id + локальная лента.
  Future<void> clearDialogHistory(String dlgId) async {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    if (!isDialogHistoryReady(dlgId) &&
        _connectionStatus == ConnectionStatus.connected &&
        _api.isConnected) {
      await loadMessages(dlgId, force: true);
    }
    final ids = dialog.messages
        .map((m) => m.id.trim().isNotEmpty ? m.id.trim() : m.hash.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isNotEmpty) {
      _removeMessagesFromDialog(dialog, ids);
      final usrId = (_profile?.id ?? '').trim();
      if (usrId.isNotEmpty &&
          _connectionStatus == ConnectionStatus.connected &&
          _api.isConnected) {
        _api.sendMsgDel(usrId: usrId, dlgId: dlgId, ids: ids.join(','));
      }
    } else {
      dialog.messages.clear();
      dialog.last_msg = '';
    }
    await ForumCache.instance.deleteMessagesFile(dlgId);
    notifyListeners();
  }

  /// Удалить один чат из списка (`del_dlg` + локально).
  Future<void> deleteDialog(String dlgId) async {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    final id = dialog.id?.trim() ?? dlgId.trim();
    if (id.isEmpty) return;

    try {
      if (_connectionStatus == ConnectionStatus.connected && _api.isConnected) {
        final resp = await _api.sendDlgDel(id);
        if (resp['success'] == false) {
          throw StateError(
            resp['message']?.toString() ?? 'Не удалось удалить чат',
          );
        }
      }
    } catch (e) {
      // Не трогаем список — иначе dlg_list вернёт чат обратно.
      rethrow;
    }

    _suppressDlg(id);
    _removeDialogLocally(id);
  }

  /// Покинуть группу: WS [`dlg_usr_del`](https://4um.me:7770/api_forum_doc/)
  /// с `dlg_usr_id` = текущий пользователь.
  Future<void> leaveGroup(String dlgId) async {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    final id = dialog.id?.trim() ?? dlgId.trim();
    final me = _profile?.id.trim() ?? '';
    if (id.isEmpty || me.isEmpty) {
      throw StateError('Нет профиля для выхода из группы');
    }

    try {
      if (_connectionStatus == ConnectionStatus.connected && _api.isConnected) {
        final resp = await _api.sendDlgUsrDel(dlgId: id, dlgUsrId: me);
        if (resp['success'] == false) {
          final msg = resp['message']?.toString().trim() ?? '';
          throw StateError(
            msg.isNotEmpty
                ? msg
                : 'Не удалось покинуть группу. '
                    'Если вы владелец — сначала назначьте администратора.',
          );
        }
      } else {
        throw StateError('Нет подключения к серверу');
      }
    } catch (e) {
      rethrow;
    }

    _suppressDlg(id);
    _removeDialogLocally(id);
  }

  void _suppressDlg(String dlgId) {
    final key = dlgId.trim();
    if (key.isEmpty) return;
    _suppressedDlgIds.removeWhere((id) => _sameDlgId(id, key));
    _suppressedDlgIds.add(key);
  }

  bool _isSuppressedDlg(String? dlgId) {
    final key = dlgId?.trim() ?? '';
    if (key.isEmpty) return false;
    return _suppressedDlgIds.any((id) => _sameDlgId(id, key));
  }

  void _removeDialogLocally(String dlgId) {
    _removePrefKey(_mutedUntil, dlgId);
    _removePrefId(_archivedIds, dlgId);
    unawaited(_saveDialogLocalPrefs());
    _selectedDialogIds
      ..clear()
      ..add(dlgId);
    deleteSelectedDialogsFromSelectMode();
  }

  /// Первая страница истории (до ~100) уже получена для диалога в этой сессии.
  bool isDialogHistoryReady(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return false;
    return _messagesLoadedFor.any((id) => _sameDlgId(id, dlgId));
  }

  bool isDialogHistoryLoading(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return false;
    if (isDialogHistoryReady(dlgId)) return false;
    if (_messageLoadsInFlight.keys.any((id) => _sameDlgId(id, dlgId))) {
      return true;
    }
    return _messagesLoading && _sameDlgId(_selectedId, dlgId);
  }
  String? get messagesError => _messagesError;

  MessageViewModel? _replyToMessage;
  MessageViewModel? get replyToMessage => _replyToMessage;

  /// Сообщение в режиме редактирования (как iOS isEditMode).
  MessageViewModel? _editingMessage;
  MessageViewModel? get editingMessage => _editingMessage;

  /// Закреплённые msg_id по dlg_id.
  final Map<String, Set<String>> _pinnedMsgIds = {};

  /// Текст композера текущего чата (для flush `typing` при уходе).
  String _composerText = '';

  /// Локальные черновики по `dlg_id` — превью «Черновик:» в списке чатов.
  final Map<String, String> _composerDrafts = {};

  /// Черновик из `dlg_info` → `users[].typing` для подстановки в инпут.
  String? _pendingComposerDraft;
  String? _pendingComposerDraftDlgId;
  int _composerDraftEpoch = 0;
  int get composerDraftEpoch => _composerDraftEpoch;

  DateTime? _lastTypingSentAt;
  static const _typingThrottle = Duration(milliseconds: 1500);
  static const _typingIndicatorTtl = Duration(seconds: 2);

  /// Подзаголовок «печатает…» в открытом чате.
  String? _chatTypingLabel;
  String? get chatTypingLabel => _chatTypingLabel;
  Timer? _chatTypingTimer;

  /// Временная подмена `last_msg` в списке диалогов.
  final Map<String, String> _typingListPreview = {};
  final Map<String, String> _typingSavedLastMsg = {};
  final Map<String, Timer> _typingListTimers = {};

  List<String> _quickReactions = List.of(kTelegramReactionEmojis);
  List<String> get quickReactions => List.unmodifiable(_quickReactions);

  void setReplyTo(MessageViewModel message) {
    _editingMessage = null;
    _replyToMessage = message;
    notifyListeners();
  }

  void clearReplyTo() {
    if (_replyToMessage == null) return;
    _replyToMessage = null;
    notifyListeners();
  }

  void setEditMessage(MessageViewModel message) {
    if (!message.my) return;
    if (!canEditMessage(message)) return;
    _replyToMessage = null;
    _editingMessage = message;
    notifyListeners();
  }

  /// Как в Telegram: редактирование своих сообщений в пределах 48 часов.
  static const Duration editTimeLimit = Duration(hours: 48);

  bool canEditMessage(MessageViewModel message) {
    if (!message.my || message.isCall) return false;
    if (!MsgListCursors.isSavedMessage(message)) return false;
    final created = MediaDisplayName.tryParseDttmcr(message.dttmcr);
    if (created == null) return true;
    return DateTime.now().difference(created) <= editTimeLimit;
  }

  void clearEditMessage() {
    if (_editingMessage == null) return;
    _editingMessage = null;
    notifyListeners();
  }

  bool isMessagePinned(String? dlgId, String? msgId) {
    final d = dlgId?.trim() ?? '';
    final m = msgId?.trim() ?? '';
    if (d.isEmpty || m.isEmpty) return false;
    for (final e in _pinnedMsgIds.entries) {
      if (_sameDlgId(e.key, d) && e.value.contains(m)) return true;
    }
    return false;
  }

  Future<void> togglePinMessage(
    MessageViewModel message, {
    bool forBoth = true,
  }) async {
    final dialog = selectedDialog;
    final dlgId = dialog?.id?.trim() ?? '';
    final msgId = _serverMessageId(message);
    final usrId = (_profile?.id ?? '').trim();
    if (dialog == null || dlgId.isEmpty || msgId == null || usrId.isEmpty) {
      throw StateError('Нельзя закрепить это сообщение');
    }
    final pinned = isMessagePinned(dlgId, msgId);
    final set = _pinnedMsgIds.putIfAbsent(dlgId, () => <String>{});
    if (pinned) {
      set.remove(msgId);
      _api.sendPinMsgDel(
        dlgId: dlgId,
        msgId: msgId,
        usrId: usrId,
        forBoth: forBoth,
      );
    } else {
      set.add(msgId);
      _api.sendPinMsgAdd(
        dlgId: dlgId,
        msgId: msgId,
        usrId: usrId,
        forBoth: forBoth,
      );
    }
    notifyListeners();
  }

  Future<void> sendToFavorites(MessageViewModel message) async {
    final fav = _dialogs.where((d) => d.fav).firstOrNull;
    final favId = fav?.id?.trim() ?? '';
    if (fav == null || favId.isEmpty || favId == '0') {
      throw StateError('Диалог избранного не настроен');
    }
    if (!ForwardMapper.canForward(message)) {
      throw StateError('Это сообщение нельзя добавить в избранное');
    }
    final hash = ClientMsgHash.generate();
    final payload = ForwardMapper.buildClonePayload(
      source: message,
      dlgId: favId,
      hash: hash,
    );
    // iOS шлёт grp_id в избранное.
    payload['grp_id'] = favId;
    _api.sendMsg(payload);
  }

  /// Редактирование текста/подписи своего сообщения (WS `msg` с полем `id`).
  Future<void> submitEditedMessage(String text) async {
    final editing = _editingMessage;
    final dialog = selectedDialog;
    final dlgId = dialog?.id?.trim() ?? '';
    final msgId = editing == null ? null : _serverMessageId(editing);
    final trimmed = EmoticonReplacer.replace(text.trim());
    if (editing == null || dialog == null || dlgId.isEmpty || msgId == null) {
      return;
    }
    if (trimmed.isEmpty) return;
    if (!canEditMessage(editing)) {
      clearEditMessage();
      return;
    }

    final type = ForwardMapper.serverType(editing);
    final payload = <String, dynamic>{
      'type': type,
      'id': msgId,
      'ai': 0,
    };
    _applyMsgTarget(payload, dialog);
    if (type == 'txt') {
      payload['body'] = trimmed;
    } else {
      payload['body'] = _editedAttachmentBody(editing, type, trimmed);
    }
    _api.sendMsg(payload);

    // Оптимистично обновим локально; время (dtshow) не меняем.
    final nowIso = _nowIso();
    editing.dttmup = nowIso;
    editing.editedLocal = true;
    if (type == 'txt') {
      editing.body = trimmed;
      editing.text = trimmed;
    } else {
      editing.desc = trimmed;
      editing.text = trimmed;
      if (type == 'geo') {
        editing.address = trimmed;
        editing.body = trimmed;
      } else {
        // UI-подпись; сырой JSON для повторного edit не нужен.
        editing.body = trimmed;
      }
    }
    _editingMessage = null;
    notifyListeners();
  }

  String _editedAttachmentBody(
    MessageViewModel editing,
    String type,
    String trimmed,
  ) {
    if (type == 'geo') {
      return jsonEncode({
        'lat': editing.latitude ?? 0,
        'lon': editing.longitude ?? 0,
        'adrs': trimmed,
        'desc': editing.desc.trim(),
      });
    }
    if (type == 'voice') {
      final file = editing.files.isNotEmpty ? editing.files.first : null;
      return jsonEncode({
        if (file != null) ...{
          'kind': file.kind.isNotEmpty ? file.kind : 'mp3',
          'fname': file.fname,
          'fdir': file.fdir,
          if (file.hash.isNotEmpty) 'hash': file.hash,
          'duration': file.duration.toString(),
          'size': file.size.toString(),
        },
        'desc': trimmed,
      });
    }
    if (type == 'file') {
      final title = MediaDisplayName.resolve(
        title: editing.fileTitle,
        fname: editing.files.isNotEmpty ? editing.files.first.fname : null,
        dttmcr: editing.dttmcr,
      );
      return jsonEncode({
        'desc': trimmed,
        'title': title,
        'files': editing.files
            .map(
              (f) => {
                'kind': f.kind,
                'title': MediaDisplayName.forFile(f, dttmcr: editing.dttmcr),
                'size': f.size.toString(),
                'fname': f.fname,
                'fdir': f.fdir,
                if (f.hash.isNotEmpty) 'hash': f.hash,
              },
            )
            .toList(),
      });
    }
    // media / img / video
    return jsonEncode({
      'desc': trimmed,
      'files': editing.files
          .map(
            (f) => {
              if (f.hash.isNotEmpty) 'hash': f.hash,
              'kind': f.kind,
              'fname': f.fname,
              'fdir': f.fdir,
              'size': f.size.toString(),
              'width': f.width,
              'height': f.height,
              'duration': f.duration.toString(),
              if (f.preview.isNotEmpty) 'preview': f.preview,
            },
          )
          .toList(),
    });
  }

  bool hasMoreMessages(String? dlgId) =>
      dlgId != null && (_msgHasMore[dlgId] ?? false);

  /// При открытии чата оставляем только последнюю страницу (~100).
  /// Более старые подгружаются при скролле вверх.
  bool trimDialogToLatestPage(String? dlgId) {
    final key = dlgId?.trim();
    if (key == null || key.isEmpty) return false;
    final dialog = _dialogs.where((d) => _sameDlgId(d.id, key)).firstOrNull;
    if (dialog == null) return false;

    const page = MsgListResult.historyPageSize;
    if (dialog.messages.length <= page) return false;

    dialog.messages = List<MessageViewModel>.of(
      dialog.messages.sublist(dialog.messages.length - page),
    );
    MessageMapper.applyGrouping(
      dialog.messages,
      isGroupChat: dialog.isGrp,
    );
    _msgHasMore[key] = true;
    return true;
  }

  ChatScrollAnchor? chatScrollAnchor(String? dlgId) {
    if (dlgId == null) return null;
    final direct = _chatScrollAnchors[dlgId.trim()];
    if (direct != null) return direct;
    for (final entry in _chatScrollAnchors.entries) {
      if (_sameDlgId(entry.key, dlgId)) return entry.value;
    }
    return null;
  }

  void saveChatScrollAnchor(
    String dlgId, {
    required double pixels,
    required double maxExtent,
    String? messageRef,
    double offsetFromTop = 0,
  }) {
    if (pixels.isNaN || maxExtent.isNaN) return;

    final ref = messageRef?.trim();
    final hasMessage = ref != null && ref.isNotEmpty;
    final hasScroll = pixels > 0 || maxExtent > 0;
    if (!hasMessage && !hasScroll) return;

    final key = dlgId.trim();
    final existing = chatScrollAnchor(key);
    if (existing != null &&
        !hasMessage &&
        pixels <= 0 &&
        maxExtent <= 0 &&
        existing.hasMessageRef) {
      return;
    }

    final anchor = ChatScrollAnchor(
      pixels: pixels,
      maxExtent: maxExtent,
      messageRef: hasMessage ? ref : existing?.messageRef,
      offsetFromTop: hasMessage ? offsetFromTop : (existing?.offsetFromTop ?? offsetFromTop),
    );
    _chatScrollAnchors[key] = anchor;
    ForumCache.instance.saveScrollAnchor(key, anchor.toJson());
  }

  void registerChatScrollSaver(String dlgId, void Function() saver) {
    _chatScrollSavers[dlgId.trim()] = saver;
  }

  void unregisterChatScrollSaver(String dlgId) {
    final key = dlgId.trim();
    _chatScrollSavers.remove(key);
    for (final k in List.of(_chatScrollSavers.keys)) {
      if (_sameDlgId(k, key)) _chatScrollSavers.remove(k);
    }
  }

  void _flushChatScroll(String? dlgId) {
    if (dlgId == null) return;
    final key = dlgId.trim();
    _chatScrollSavers[key]?.call();
    for (final entry in _chatScrollSavers.entries) {
      if (_sameDlgId(entry.key, key)) entry.value.call();
    }
  }

  Future<void> preloadChatScrollAnchor(String dlgId) async {
    final key = dlgId.trim();
    if (_chatScrollAnchors.containsKey(key)) return;
    for (final k in _chatScrollAnchors.keys) {
      if (_sameDlgId(k, key)) return;
    }
    final map = await ForumCache.instance.loadScrollAnchor(key);
    if (map == null) return;
    _chatScrollAnchors[key] = ChatScrollAnchor.fromJson(map);
  }

  /// Сравнение dlg_id (строка / число).
  static bool dlgIdsEqual(String? a, String? b) => _sameDlgId(a, b);

  Future<void> initialize() async {
    final cachedAppearance = await AppearancePrefs.load();
    if (cachedAppearance != null) {
      _appearance = cachedAppearance;
    }
    await _loadDialogLocalPrefs();
    await _loadDatabaseCatalogs();

    final token = await AuthSession.loadToken();
    ApiConfig.setSessionToken(token);
    _isAuthenticated = token != null && token.isNotEmpty;
    _authReady = true;
    notifyListeners();

    if (!_isAuthenticated) {
      return;
    }
    return _bootstrap();
  }

  /// Страны для экрана телефона (`database.countries`).
  Future<List<AuthCountry>> loadAuthCountries() async {
    try {
      final resp = await _api.fetchDatabase();
      return AuthCountry.listFromDatabase(resp);
    } catch (_) {
      return const [AuthCountry.russia];
    }
  }

  /// После SMS / QR: сохранить JWT и сразу показать Home.
  /// Bootstrap (WS / контакты) идёт в фоне — не блокирует экран кода.
  Future<void> completeAuthentication({
    required String token,
    String? userId,
    String? phone,
  }) async {
    await AuthSession.save(
      token: token,
      userId: userId,
      phone: phone,
    );
    ApiConfig.setSessionToken(token);
    _isAuthenticated = true;
    notifyListeners();
    unawaited(_bootstrap());
  }

  bool _loggingOut = false;

  /// Выход: очистка сессии, кредов и всех локальных кэшей, возврат на онбординг.
  /// [sendToServer] = false — принудительный выход по `action: log_out`
  /// (сервер уже отвязал устройство, повторный WS `log_out` не нужен).
  Future<void> logOut({bool sendToServer = true}) async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      if (sendToServer) {
        try {
          if (_api.isConnected) {
            final uid = await DeviceIdService.getOrCreate();
            await _api.sendWs({
              'type': 'log_out',
              'data': {'uid': uid},
            });
          }
        } catch (_) {}
      }
      await _api.disconnect();
      await AuthSession.clear();
      ApiConfig.setSessionToken(null);
      await CallManager.instance.shutdown();
      await ForumCache.instance.clearAll();
      await DialogLocalPrefs.clear();
      _mutedUntil.clear();
      _archivedIds.clear();
      _muteExpiryTimer?.cancel();
      _muteExpiryTimer = null;
      _stopDialogsLiveSync();
      _profile = null;
      _dialogs = [];
      _groups = [];
      _pendingUnknownDialogPushes.clear();
      _unknownDialogRefreshQueued.clear();
      _unknownDialogRefreshAttempts.clear();
      _unknownDialogRefreshInFlight = null;
      _selectedId = null;
      _messagesLoadedFor.clear();
      _msgHasMore.clear();
      _messageLoadsInFlight.clear();
      _deletedMessageIds.clear();
      _chatScrollAnchors.clear();
      _chatScrollSavers.clear();
      _readAckSent.clear();
      _isAuthenticated = false;
      _connectionStatus = ConnectionStatus.idle;
      _connectionError = null;
      notifyListeners();
    } finally {
      _loggingOut = false;
    }
  }

  /// `action: log_out` из сокета — тихий выход без подтверждения.
  void _onForceLogOut() {
    unawaited(logOut(sendToServer: false));
  }

  // ---------------------------------------------------------------------------
  // Устройства (device_list / device_del / device_del_all, как в Forum_ios)
  // ---------------------------------------------------------------------------

  String? _deviceUid;

  /// UID текущего устройства (тот же, что в check_code / get_qr / log_in).
  String? get deviceUid => _deviceUid;

  Future<String> currentDeviceUid() async {
    return _deviceUid ??= await DeviceIdService.getOrCreate();
  }

  /// WS `device_list` — активные сеансы пользователя.
  Future<List<DeviceSession>> loadDevices() async {
    await currentDeviceUid();
    return _api.fetchDeviceList();
  }

  /// WS `device_del` — отключить устройство по uid.
  Future<void> terminateDevice(String uid) => _api.deviceDel(uid);

  /// WS `device_del_all` — завершить все сеансы, кроме текущего.
  Future<void> terminateAllOtherSessions() => _api.deviceDelAll();

  /// WS `check_qr` — авторизовать другое устройство по строке из его QR.
  Future<void> authorizeByQr(String qr) => _api.checkQr(qr);

  Future<void> _configureCalls() async {
    final token = ApiConfig.token;
    final profile = _profile;
    if (token.isEmpty || profile == null) return;
    try {
      await CallManager.instance.configure(
        userId: profile.id,
        userName: profile.name,
        sessionToken: token,
      );
      CallManager.instance.onCallChatResult = _insertCallChatMessage;
      final fcm = FirebaseService.instance.fcmToken;
      if (fcm.isNotEmpty) {
        CallManager.instance.registerVoipToken(fcm);
      }
    } catch (e) {
      ApiLogger.instance.logEvent('CALL', 'configure failed: $e');
    }
  }

  /// Локальный пузырь `type=call` (msg_call.md). Серверное эхо дедупится по call_id.
  void _insertCallChatMessage(CallChatResult result) {
    var dlgId = (result.dlgId ?? '').trim();
    DialogsListViewModel? dialog;
    if (dlgId.isNotEmpty && dlgId != '0') {
      dialog = _findDialog(dlgId);
    }
    // Fallback: 1:1 по собеседнику, если в сигналинге не было dlgId.
    if (dialog == null) {
      dialog = _findDialogForCallResult(result);
      dlgId = dialog?.id?.trim() ?? dlgId;
    }
    if (dialog == null || dlgId.isEmpty || dlgId == '0') {
      ApiLogger.instance.logEvent(
        'CALL',
        'call chat msg skipped: no dialog dlgId=${result.dlgId} '
        'caller=${result.callerId} callId=${result.callId}',
      );
      return;
    }

    final me = _profile?.id;
    final isMine = CallMessageDisplay.sameUserId(result.callerId, me);
    final display = CallMessageDisplay.resolve(
      body: CallMessageBody(
        media: result.media,
        type: result.type,
        duration: result.durationSec,
        rejectUsrId: result.rejectUsrId,
        callId: result.callId,
      ),
      frId: result.callerId,
      currentUserId: me,
    );
    final preview = display.previewText;
    final callId = result.callId.trim();
    final localId = (callId.isNotEmpty && callId != 'pending')
        ? 'call_local_$callId'
        : ClientMsgHash.generate();

    final message = MessageViewModel(
      id: localId,
      type: 'call',
      my: isMine,
      body: result.bodyJson,
      text: preview,
      desc: preview,
      fr_name: result.callerName.isNotEmpty
          ? result.callerName
          : (isMine ? (_profile?.name ?? '') : ''),
      fr_id: result.callerId,
      dttmcr: _nowIso(),
      dtshow: _nowTime(),
      status: 1,
      hash: localId,
    );

    _applySingleMessage(dialog, dlgId, message);
  }

  DialogsListViewModel? _findDialogForCallResult(CallChatResult result) {
    final me = _profile?.id;
    final peerCandidates = <String>{};
    final peer = result.peerUserId.trim();
    if (peer.isNotEmpty && !CallMessageDisplay.sameUserId(peer, me)) {
      peerCandidates.add(peer);
    }
    if (!CallMessageDisplay.sameUserId(result.callerId, me)) {
      peerCandidates.add(result.callerId.trim());
    }
    if (peerCandidates.isEmpty) return null;
    for (final d in _dialogs) {
      final uid = d.usr_id?.trim() ?? '';
      if (uid.isEmpty) continue;
      for (final p in peerCandidates) {
        if (CallMessageDisplay.sameUserId(uid, p)) {
          final id = d.id?.trim() ?? '';
          if (id.isNotEmpty && id != '0') return d;
        }
      }
    }
    return null;
  }

  /// Аудио/видеозвонок из шапки чата (1:1 или группа).
  Future<void> startCallFromChat({required bool video}) async {
    final dialog = selectedDialog;
    if (dialog == null) return;

    final isGroup = dialog.isGrp || dialog.chatType == ChatType.groupChat;
    if (isGroup) {
      final dlgId = dialog.id?.trim() ?? '';
      if (dlgId.isEmpty) {
        ApiLogger.instance.logEvent('CALL', 'group call: empty dlg_id');
        return;
      }
      final participants = await _loadGroupCallParticipants(dlgId);
      if (participants.isEmpty) {
        ApiLogger.instance.logEvent(
          'CALL',
          'group call: no participants for dlg $dlgId',
        );
        return;
      }
      ApiLogger.instance.logEvent(
        'CALL',
        'start group call dlg=$dlgId peers=${participants.length} video=$video',
      );
      await CallManager.instance.startGroupCall(
        participants: participants,
        groupId: dlgId,
        title: dialog.chatName,
        dlgId: dlgId,
        video: video,
      );
      return;
    }

    final peerId = dialog.usr_id?.trim() ?? '';
    if (peerId.isEmpty) return;
    final dlgId = dialog.isNewContactWithoutDialog
        ? null
        : dialog.id;
    await CallManager.instance.startCall(
      peerId: peerId,
      peerName: dialog.chatName,
      peerAvatar: ApiConfig.resolveAssetUrl(dialog.avatar),
      dlgId: dlgId,
      video: video,
    );
  }

  Future<List<CallParticipant>> _loadGroupCallParticipants(String dlgId) async {
    try {
      final resp = await _api.sendWs({
        'type': 'dlg_info',
        'data': {
          'dlg_id': dlgId,
          if ((_profile?.id ?? '').isNotEmpty) 'usr_id': _profile!.id,
        },
      });
      final users = resp['users'];
      if (users is! List) return const [];
      final myId = _profile?.id.trim() ?? '';
      final out = <CallParticipant>[];
      for (final item in users) {
        if (item is! Map) continue;
        final uid = item['usr_id']?.toString().trim() ?? '';
        if (uid.isEmpty) continue;
        if (myId.isNotEmpty && ReactionUtils.sameUserId(uid, myId)) continue;
        out.add(CallParticipant(
          userId: uid,
          name: item['usr_name']?.toString() ??
              item['name']?.toString() ??
              '',
          avatarUrl: ApiConfig.resolveAssetUrl(
            item['usr_ava']?.toString() ?? item['ava']?.toString(),
          ),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> retryConnection() {
    _messagesLoadedFor.clear();
    _msgHasMore.clear();
    _loadGeneration++;
    return _bootstrap();
  }

  Future<void> _bootstrap() async {
    _connectionError = null;
    final hadCache = await _restoreFromCache();
    if (hadCache) {
      _connectionStatus = ConnectionStatus.connected;
      notifyListeners();
    } else {
      _connectionStatus = ConnectionStatus.connecting;
      notifyListeners();
    }

    _refreshing = true;
    notifyListeners();

    try {
      final uid = await DeviceIdService.getOrCreate();
      await _api.connect();
      _profile = await _api.login(
        uid,
        fcmToken: FirebaseService.instance.fcmToken,
      );
      _mergeServerAppearance(_profile!.appearance);
      unawaited(AppearancePrefs.save(_appearance));

      // Контакты не блокируют вход: диалог macOS может висеть бесконечно.
      final contacts = await ContactsService.loadContacts()
          .timeout(const Duration(seconds: 3), onTimeout: () => const []);

      final dialogsFuture = _api.fetchDialogs(
        contacts,
        currentUserId: _profile?.id,
      );
      final groupsFuture = _api.fetchGroups();

      _dialogs = _mergePreservingMessages(await dialogsFuture);
      _connectionStatus = ConnectionStatus.connected;
      _connectionError = null;
      _ensureDefaultSelection();
      notifyListeners();
      _startDialogsLiveSync();

      try {
        _groups = await groupsFuture;
      } on ForumApiException {
        // Папки не критичны.
      }

      unawaited(_loadEmojiCatalog());
      unawaited(_resendPendingMessages());
      unawaited(_configureCalls());

      if (_selectedId != null) {
        loadMessages(_selectedId!, force: true);
      }
    } on ForumApiException catch (e) {
      if (!hadCache) {
        _connectionStatus = ConnectionStatus.error;
      }
      _connectionError = e.message;
    } catch (e) {
      if (!hadCache) {
        _connectionStatus = ConnectionStatus.error;
      }
      _connectionError = e.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<bool> _restoreFromCache() async {
    var restored = false;
    final cache = ForumCache.instance;

    final profileMap = await cache.loadProfile();
    if (profileMap != null) {
      _profile = UserProfile.fromJson(profileMap);
      _mergeServerAppearance(_profile!.appearance);
      restored = true;
    }

    final dialogsMap = await cache.loadDialogs();
    if (dialogsMap != null && dialogsMap['success'] == true) {
      _dialogs = _api.parseDialogsResponse(
        dialogsMap,
        currentUserId: _profile?.id,
      );
      _applyLocalDialogPrefs(_dialogs);
      restored = _dialogs.isNotEmpty || restored;
    }

    final groupsMap = await cache.loadGroups();
    if (groupsMap != null && groupsMap['success'] == true) {
      _groups = _api.parseGroupsResponse(groupsMap);
    }

    _ensureDefaultSelection();

    if (_selectedId != null) {
      await _restoreMessagesFromCache(_selectedId!);
      await preloadChatScrollAnchor(_selectedId!);
    }

    for (final dialog in _dialogs) {
      final id = dialog.id?.trim();
      if (id == null || id.isEmpty) continue;
      await _ensureDeletedMessageIdsLoaded(id);
      if (dialog.messages.isNotEmpty) {
        await preloadChatScrollAnchor(id);
      }
    }

    return restored;
  }

  Future<void> _restoreMessagesFromCache(String dlgId) async {
    await _ensureDeletedMessageIdsLoaded(dlgId);

    final map = await ForumCache.instance.loadMessages(dlgId);
    if (map == null || map['success'] != true) return;

    final dialog = _findDialog(dlgId);
    if (dialog == null) return;

    try {
      final result = _api.parseMsgListResponse(
        map,
        expectedDlgId: dlgId,
        currentUserId: _profile?.id,
        currentUserName: _reactionAuthorName,
        isGroupChat: dialog.isGrp,
      );
      if (result.messages.isEmpty) return;
      var messages = _withoutDeletedMessages(dlgId, result.messages);
      // В кэше могла скопиться вся история — для UI берём только хвост.
      const page = MsgListResult.historyPageSize;
      if (messages.length > page) {
        messages = messages.sublist(messages.length - page);
        _msgHasMore[dlgId] = true;
      } else {
        _msgHasMore[dlgId] = result.hasMoreHistory;
      }
      dialog.messages = messages;
      MessageMapper.applyGrouping(
        dialog.messages,
        isGroupChat: dialog.isGrp,
      );
    } catch (_) {}
  }

  Future<void> _ensureDeletedMessageIdsLoaded(String dlgId) async {
    if (_deletedMessageIds.containsKey(dlgId)) return;
    final ids = await ForumCache.instance.loadDeletedMessageIds(dlgId);
    _deletedMessageIds[dlgId] = ids;
  }

  List<MessageViewModel> _withoutDeletedMessages(
    String dlgId,
    List<MessageViewModel> messages,
  ) {
    final deleted = _deletedMessageIds[dlgId];
    if (deleted == null || deleted.isEmpty) {
      return List<MessageViewModel>.from(messages);
    }
    return messages
        .where(
          (m) =>
              !_messageMatchesAnyDeletedId(m, deleted),
        )
        .toList();
  }

  bool _messageMatchesAnyDeletedId(
    MessageViewModel message,
    Set<String> deleted,
  ) {
    final id = message.id.trim();
    final hash = message.hash.trim();
    if (id.isNotEmpty && deleted.contains(id)) return true;
    if (hash.isNotEmpty && deleted.contains(hash)) return true;
    return false;
  }

  void _filterDeletedMessagesInDialog(DialogsListViewModel dialog) {
    final dlgId = dialog.id?.trim();
    if (dlgId == null || dlgId.isEmpty) return;
    final deleted = _deletedMessageIds[dlgId];
    if (deleted == null || deleted.isEmpty) return;

    final before = dialog.messages.length;
    dialog.messages = dialog.messages
        .where((m) => !_messageMatchesAnyDeletedId(m, deleted))
        .toList();
    if (dialog.messages.length != before) {
      MessageMapper.applyGrouping(
        dialog.messages,
        isGroupChat: dialog.isGrp,
      );
    }
  }

  Future<void> _rememberDeletedMessages(
    String dlgId,
    Iterable<String> ids,
  ) async {
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (clean.isEmpty) return;

    final set = _deletedMessageIds.putIfAbsent(dlgId, () => <String>{});
    set.addAll(clean);

    await ForumCache.instance.addDeletedMessageIds(dlgId, clean);
    await ForumCache.instance.removeMessagesFromCache(dlgId, clean);
  }

  void _ensureDefaultSelection() {
    // При старте чат не выбираем — пустая панель «Выберите, кому…».
    if (_selectedId == null) return;
    final stillExists = _dialogs.any((d) => _sameDlgId(d.id, _selectedId));
    if (!stillExists) {
      _selectedId = null;
    }
  }

  void setNavTab(BottomNavTab tab) {
    if (_navTab == BottomNavTab.chats && tab != BottomNavTab.chats) {
      for (final saver in _chatScrollSavers.values) {
        saver();
      }
    }
    _navTab = tab;
    notifyListeners();
  }

  void toggleTheme() {
    _appearance = _appearance.copyWith(
      theme: isDark ? AppearanceTheme.light : AppearanceTheme.dark,
    );
    unawaited(AppearancePrefs.save(_appearance));
    notifyListeners();
  }

  void previewAppearance(AppearanceSettings settings) {
    _appearance = settings;
    notifyListeners();
  }

  /// Сервер отдаёт только часть полей оформления — остальное оставляем локально.
  void _mergeServerAppearance(AppearanceSettings server) {
    _appearance = _appearance.copyWith(
      avatarColorId: server.avatarColorId,
      nameColorId: server.nameColorId,
      bgImg: server.bgImg,
    );
  }

  Future<String?> saveAppearance(AppearanceSettings settings) async {
    _appearance = settings;
    notifyListeners();

    if (_connectionStatus == ConnectionStatus.connected && _api.isConnected) {
      try {
        final payload = settings.toProfilePayload();
        final resp = await _api.changeProfile(payload);
        if (resp['success'] != true) {
          final msg = resp['message']?.toString() ?? 'Не удалось сохранить';
          await AppearancePrefs.save(settings);
          notifyListeners();
          return msg;
        }

        final userJson = parseChangeProfileUser(resp);
        if (userJson != null && _profile != null) {
          final mergedMap = mergeProfileAppearance(userJson, payload);
          _profile = UserProfile.fromJson(mergedMap);
          _appearance = settings.copyWith(
            avatarColorId: _profile!.appearance.avatarColorId,
            nameColorId: _profile!.appearance.nameColorId,
            bgImg: _profile!.appearance.bgImg,
          );
          await ForumCache.instance.saveProfile(_profile!.toJson());
        } else if (_profile != null) {
          _profile = _profile!.copyWith(appearance: settings);
          await ForumCache.instance.saveProfile(_profile!.toJson());
        }
      } on ForumApiException catch (e) {
        await AppearancePrefs.save(settings);
        notifyListeners();
        return e.message;
      }
    }

    await AppearancePrefs.save(settings);
    notifyListeners();
    return null;
  }

  Future<String?> updateProfileAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return 'Нет подключения к серверу';
    }

    _profileAvatarUploading = true;
    notifyListeners();
    try {
      final prepared = await MediaPreprocessor.prepare(
        bytes: bytes,
        originalName: fileName,
      );
      final uploaded = await _api.uploadMediaAttachment(
        bytes: prepared.bytes,
        originalName: prepared.fileName,
      );
      final avaPath = avatarPathFromUpload(uploaded);
      if (_profile != null) {
        _profile = _profile!.copyWith(avatarUrl: avaPath);
        notifyListeners();
      }
      return await _changeProfileFields({'ava': avaPath});
    } on FileUploadException catch (e) {
      return e.message;
    } on ForumApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    } finally {
      _profileAvatarUploading = false;
      notifyListeners();
    }
  }

  Future<String?> removeProfileAvatar() => _changeProfileFields({'ava': ''});

  Future<String?> _changeProfileFields(Map<String, dynamic> fields) async {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return 'Нет подключения к серверу';
    }

    try {
      final resp = await _api.changeProfile(fields);
      if (resp['success'] != true) {
        return resp['message']?.toString() ?? 'Не удалось сохранить профиль';
      }

      final userJson = parseChangeProfileUser(resp);
      if (userJson != null) {
        final base = _profile?.toJson() ?? userJson;
        _profile = UserProfile.fromJson(mergeProfileAppearance(base, userJson));
        await ForumCache.instance.saveProfile(_profile!.toJson());
      } else if (_profile != null && fields.containsKey('ava')) {
        _profile = _profile!.copyWith(
          avatarUrl: fields['ava']?.toString() ?? '',
        );
        await ForumCache.instance.saveProfile(_profile!.toJson());
      }
      notifyListeners();
      return null;
    } on ForumApiException catch (e) {
      return e.message;
    }
  }

  Future<void> _loadDatabaseCatalogs() async {
    final cache = ForumCache.instance;
    final cached = await cache.loadDatabase();
    if (cached != null && cached['success'] == true) {
      final data = cached['data'];
      if (data is Map) {
        _database = ForumDatabase.fromResponse(Map<String, dynamic>.from(data));
        notifyListeners();
      }
    }

    try {
      final resp = await _api.fetchDatabase();
      final data = resp['data'];
      if (data is Map) {
        _database = ForumDatabase.fromResponse(Map<String, dynamic>.from(data));
        notifyListeners();
      }
    } catch (_) {
      // Оставляем кэш или дефолтные палитры.
    }
  }

  void selectTab(String tabId) {
    _activeTab = tabId;
    closeGlobalSearchRibbon();
    notifyListeners();
  }

  void setSearch(String value) {
    _search = value;
    if (_shouldPreloadGlobalSearch()) {
      _scheduleGlobalSearchPreload();
    } else {
      _cancelGlobalSearchPreload();
    }
    notifyListeners();
  }

  void openGlobalSearchRibbon() {
    if (_globalSearchRibbonVisible) return;
    _globalSearchRibbonVisible = true;
    _scheduleGlobalSearchPreload();
    notifyListeners();
  }

  void closeGlobalSearchRibbon() {
    if (!_globalSearchRibbonVisible && _activeGlobalSearchHitKey == null) {
      return;
    }
    _cancelGlobalSearchPreload();
    _globalSearchRibbonVisible = false;
    _activeGlobalSearchHitKey = null;
    notifyListeners();
  }

  void setGlobalSearchScope(GlobalSearchScope scope) {
    if (_globalSearchScope == scope) return;
    _globalSearchScope = scope;
    if (_shouldPreloadGlobalSearch()) {
      _scheduleGlobalSearchPreload();
    } else {
      _cancelGlobalSearchPreload();
    }
    notifyListeners();
  }

  bool _shouldPreloadGlobalSearch() {
    return _globalSearchRibbonVisible &&
        _globalSearchScope != GlobalSearchScope.chats &&
        _search.trim().isNotEmpty &&
        _connectionStatus == ConnectionStatus.connected;
  }

  void _scheduleGlobalSearchPreload() {
    _globalSearchPreloadDebounce?.cancel();
    if (!_shouldPreloadGlobalSearch()) return;
    _globalSearchPreloadDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runGlobalSearchPreload());
    });
  }

  void _cancelGlobalSearchPreload() {
    _globalSearchPreloadDebounce?.cancel();
    _globalSearchPreloadDebounce = null;
    _globalSearchPreloadToken++;
    if (_globalSearchPreloading) {
      _globalSearchPreloading = false;
      _globalSearchPreloadDone = 0;
      _globalSearchPreloadTotal = 0;
    }
  }

  Future<void> _runGlobalSearchPreload() async {
    if (!_shouldPreloadGlobalSearch()) return;

    final token = ++_globalSearchPreloadToken;
    _globalSearchPreloading = true;
    _globalSearchPreloadDone = 0;

    final dialogs = _dialogsForActiveTab()
        .where((d) {
          final id = d.id?.trim() ?? '';
          return id.isNotEmpty &&
              !DialogsListViewModel.isPlaceholderDlgId(id);
        })
        .toList();
    _globalSearchPreloadTotal = dialogs.length;
    notifyListeners();

    try {
      for (final dialog in dialogs) {
        if (token != _globalSearchPreloadToken || !_shouldPreloadGlobalSearch()) {
          return;
        }
        final dlgId = dialog.id!.trim();
        await _ensureDialogHistoryForSearch(dlgId, dialog, token);
        if (token != _globalSearchPreloadToken) return;
        _globalSearchPreloadDone++;
        notifyListeners();
      }
    } finally {
      if (token == _globalSearchPreloadToken) {
        _globalSearchPreloading = false;
        _globalSearchPreloadDone = 0;
        _globalSearchPreloadTotal = 0;
        notifyListeners();
      }
    }
  }

  Future<void> _ensureDialogHistoryForSearch(
    String dlgId,
    DialogsListViewModel dialog,
    int token,
  ) async {
    if (token != _globalSearchPreloadToken) return;

    await _ensureDeletedMessageIdsLoaded(dlgId);
    if (dialog.messages.isEmpty) {
      await _restoreMessagesFromCache(dlgId);
    }
    if (token != _globalSearchPreloadToken) return;

    if (dialog.messages.isEmpty) {
      await _loadMessagesForSearch(dlgId, dialog, token);
    } else if (!_messagesLoadedFor.contains(dlgId)) {
      _messagesLoadedFor.add(dlgId);
    }
    if (token != _globalSearchPreloadToken) return;

    while ((_msgHasMore[dlgId] ?? false) && token == _globalSearchPreloadToken) {
      await _loadOlderMessagesPage(dlgId, dialog);
      if (token != _globalSearchPreloadToken) return;
    }
  }

  Future<void> _loadMessagesForSearch(
    String dlgId,
    DialogsListViewModel dialog,
    int token,
  ) async {
    if (_messagesLoadedFor.contains(dlgId)) return;

    final existing = _messageLoadsInFlight[dlgId];
    if (existing != null) {
      await existing;
      return;
    }

    final future = _loadMessagesForSearchImpl(dlgId, dialog, token);
    _messageLoadsInFlight[dlgId] = future;
    try {
      await future;
    } finally {
      _messageLoadsInFlight.remove(dlgId);
    }
  }

  Future<void> _loadMessagesForSearchImpl(
    String dlgId,
    DialogsListViewModel dialog,
    int token,
  ) async {
    if (_messagesLoadedFor.contains(dlgId)) return;
    if (token != _globalSearchPreloadToken) return;

    await _ensureDeletedMessageIdsLoaded(dlgId);
    await _restoreMessagesFromCache(dlgId);
    if (dialog.messages.isNotEmpty) {
      _messagesLoadedFor.add(dlgId);
      return;
    }
    if (token != _globalSearchPreloadToken) return;

    try {
      final result = await _api.fetchMessageList(
        dlgId,
        request: MsgListRequest.initial(),
        currentUserId: _profile?.id,
        currentUserName: _reactionAuthorName,
        isGroupChat: dialog.isGrp,
      );
      if (token != _globalSearchPreloadToken) return;

      final filtered = MsgListResult(
        messages: _withoutDeletedMessages(dlgId, result.messages),
        isHistory: result.isHistory,
        responseFirstId: result.responseFirstId,
        hasMoreHistory: result.hasMoreHistory,
      );
      MsgListMerge.apply(
        dialog: dialog,
        result: filtered,
        replace: true,
        onHistoryPagination: (hasMore) => _msgHasMore[dlgId] = hasMore,
      );
      _filterDeletedMessagesInDialog(dialog);
      final deleted = _deletedMessageIds[dlgId];
      if (deleted != null && deleted.isNotEmpty) {
        unawaited(
          ForumCache.instance.removeMessagesFromCache(dlgId, deleted),
        );
      }
      _messagesLoadedFor.add(dlgId);
    } catch (_) {}
  }

  List<GlobalSearchHit> get globalSearchHits {
    return [
      for (final g in globalSearchChatGroups) ...g.hits,
    ];
  }

  /// Чаты с найденными медиа/файлами (как в Telegram).
  List<GlobalSearchChatGroup> get globalSearchChatGroups {
    if (!_globalSearchRibbonVisible || _search.trim().isEmpty) {
      return const [];
    }
    if (_globalSearchScope == GlobalSearchScope.chats) return const [];
    return GlobalSearch.searchMediaGrouped(
      _dialogsForActiveTab(),
      _search,
      _globalSearchScope,
    );
  }

  bool get showsGlobalMediaSearch =>
      _globalSearchRibbonVisible &&
      _globalSearchScope != GlobalSearchScope.chats &&
      _search.trim().isNotEmpty;

  /// Запрос открыть поиск в чате (например, из профиля собеседника).
  void requestChatSearch(String dlgId) {
    final id = dlgId.trim();
    if (id.isEmpty) return;
    _chatSearchRequestDlgId = id;
    notifyListeners();
  }

  void clearChatSearchRequest({bool notify = true}) {
    if (_chatSearchRequestDlgId == null) return;
    _chatSearchRequestDlgId = null;
    if (notify) notifyListeners();
  }

  void clearOpenMessageRequest({bool notify = true}) {
    if (_openMessageRequestDlgId == null && _openMessageRequestId == null) {
      return;
    }
    _openMessageRequestDlgId = null;
    _openMessageRequestId = null;
    if (notify) notifyListeners();
  }

  void requestOpenMessage({
    required String dlgId,
    required String messageId,
  }) {
    final id = dlgId.trim();
    final msgId = messageId.trim();
    if (id.isEmpty || msgId.isEmpty) return;
    _openMessageRequestDlgId = id;
    _openMessageRequestId = msgId;
    notifyListeners();
  }

  Future<void> openGlobalSearchHit(GlobalSearchHit hit) async {
    final dlgId = hit.dialogId;
    if (dlgId.isEmpty) return;

    // Ленту поиска не закрываем — как в Telegram остаётся окно результатов.
    _activeGlobalSearchHitKey = hit.selectionKey;
    _openMessageRequestDlgId = dlgId;
    _openMessageRequestId = hit.messageRef.trim();

    if (_sameDlgId(_selectedId, dlgId)) {
      notifyListeners();
      return;
    }
    await selectDialog(dlgId, closeGlobalSearch: false);
  }

  /// Вкладки: Все, ИИ, Личное + папки с сервера.
  List<({String id, String label})> get tabs {
    final items = <({String id, String label})>[
      (id: BuiltinTab.all, label: 'Все'),
      if (_archivedIds.isNotEmpty)
        (id: BuiltinTab.archive, label: 'Архив'),
      (id: BuiltinTab.ai, label: 'ИИ'),
      (id: BuiltinTab.personal, label: 'Личное'),
    ];
    for (final g in _groups) {
      items.add((id: g.id, label: g.name.trim()));
    }
    return items;
  }

  /// Элементы для экрана сортировки папок.
  List<({String id, String label, bool canReorder})> get folderSortItems {
    return [
      (id: BuiltinTab.all, label: 'Все', canReorder: false),
      (id: BuiltinTab.ai, label: 'ИИ', canReorder: false),
      (id: BuiltinTab.personal, label: 'Личное', canReorder: false),
      ..._groups.map(
        (g) => (id: g.id, label: g.name.trim(), canReorder: true),
      ),
    ];
  }

  DialogGroup? groupById(String id) =>
      _groups.where((g) => g.id == id).firstOrNull;

  bool isUserFolderTab(String tabId) => !BuiltinTab.isBuiltin(tabId);

  /// Перезагрузка папок с сервера (`dlg_grp_list`).
  Future<void> refreshFolders() async {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }
    try {
      _groups = await _api.fetchGroups();
      if (!BuiltinTab.isBuiltin(_activeTab) &&
          _groups.every((g) => g.id != _activeTab)) {
        _activeTab = BuiltinTab.all;
      }
      notifyListeners();
    } on ForumApiException {
      // ignore
    }
  }

  /// Создать папку: `name` + `list` (dlg_id через запятую).
  Future<void> createFolder({
    required String name,
    required List<String> dialogIds,
    bool selectAfterCreate = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    await _api.sendDlgGrp(
      name: trimmed,
      list: FolderListCodec.encode(dialogIds),
    );
    await refreshFolders();
    final created = _groups.where((g) => g.name == trimmed).firstOrNull;
    if (created != null && selectAfterCreate) {
      _activeTab = created.id;
      notifyListeners();
    }
  }

  /// Создать группу: WS `dlg` → вставить карточку из ответа → обновить dlg_list.
  Future<void> createGroup({
    required String name,
    required List<String> userIds,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      throw ForumApiException('Нет подключения к серверу');
    }

    final created = await _api.sendCreateGroup(
      name: trimmed,
      userIds: userIds,
      currentUserId: _profile?.id,
    );

    final createdId = created.id?.trim() ?? '';
    if (createdId.isEmpty) {
      throw ForumApiException('Сервер не вернул id группы');
    }

    _upsertDialog(created);
    notifyListeners();
    await selectDialog(createdId);

    // Как iOS getDialogsList после openCreatedGroup.
    try {
      await refreshDialogs();
    } catch (_) {
      // Карточка из ответа `dlg` уже в списке.
    }
    if (!_dialogs.any((d) => _sameDlgId(d.id, createdId))) {
      _upsertDialog(created);
      notifyListeners();
    }
    if (!_sameDlgId(_selectedId, createdId)) {
      await selectDialog(createdId);
    }
  }

  void _upsertDialog(DialogsListViewModel dialog) {
    final id = dialog.id?.trim() ?? '';
    if (id.isEmpty) return;
    final idx = _dialogs.indexWhere((d) => _sameDlgId(d.id, id));
    if (idx >= 0) {
      final old = _dialogs[idx];
      if (old.messages.isNotEmpty && dialog.messages.isEmpty) {
        dialog.messages = List.of(old.messages);
      }
      _dialogs[idx] = dialog;
    } else {
      _dialogs.insert(0, dialog);
    }
  }

  /// Перезагрузить список диалогов с сервера (после создания группы и т.п.).
  Future<void> refreshDialogs() async {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }
    final existing = _refreshDialogsInFlight;
    if (existing != null) return existing;

    final future = _refreshDialogsBody();
    _refreshDialogsInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_refreshDialogsInFlight, future)) {
        _refreshDialogsInFlight = null;
      }
    }
  }

  Future<void> _refreshDialogsBody() async {
    try {
      final beforeIds = <String>{
        for (final d in _dialogs)
          if ((d.id ?? '').trim().isNotEmpty) d.id!.trim(),
      };
      final contacts = await ContactsService.loadContacts()
          .timeout(const Duration(seconds: 3), onTimeout: () => const []);
      final incoming = await _api.fetchDialogs(
        contacts,
        currentUserId: _profile?.id,
      );
      // Подавленные (покинутые) чаты не возвращаем, пока сервер их чистит.
      final filtered = incoming
          .where((d) => !_isSuppressedDlg(d.id))
          .toList(growable: true);
      // Если сервер уже не отдаёт чат — можно снять suppress.
      _suppressedDlgIds.removeWhere(
        (id) => !incoming.any((d) => _sameDlgId(d.id, id)),
      );
      _dialogs = _mergePreservingMessages(filtered);
      _ensureDefaultSelection();

      final added = <String>[];
      for (final d in _dialogs) {
        final id = d.id?.trim() ?? '';
        if (id.isEmpty || beforeIds.contains(id)) continue;
        // Числовое сравнение: "1469" vs уже известные.
        if (beforeIds.any((old) => _sameDlgId(old, id))) continue;
        added.add(id);
      }
      if (added.isNotEmpty) {
        ApiLogger.instance.logEvent(
          'DLG_LIST',
          'новые чаты без перезапуска: ${added.join(",")}',
        );
      }
      notifyListeners();
    } on ForumApiException {
      // ignore — группа уже создана на сервере
    } catch (_) {
      // ignore
    }
  }

  /// Фокус окна / resume — сразу подтянуть список (новые группы).
  void onAppResumed() {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }
    unawaited(refreshDialogs());
  }

  void _onChatRelatedPush() {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }
    unawaited(refreshDialogs());
  }

  void _startDialogsLiveSync() {
    _dialogsPollTimer?.cancel();
    _dialogsPollTimer = Timer.periodic(_dialogsPollInterval, (_) {
      if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
        return;
      }
      unawaited(refreshDialogs());
    });
  }

  void _stopDialogsLiveSync() {
    _dialogsPollTimer?.cancel();
    _dialogsPollTimer = null;
  }

  /// Переименовать пользовательскую папку.
  Future<void> renameFolder({
    required String id,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || !isUserFolderTab(id)) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    await _api.sendDlgGrp(id: id, name: trimmed);
    await refreshFolders();
  }

  /// Обновить состав чатов в папке (полный список `dlg_id`).
  Future<void> updateFolderDialogs({
    required String id,
    required List<String> dialogIds,
  }) async {
    if (!isUserFolderTab(id)) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    await _api.sendDlgGrp(
      id: id,
      list: FolderListCodec.encode(dialogIds),
    );
    await refreshFolders();
  }

  /// Удалить пользовательскую папку.
  Future<void> deleteFolder(String id) async {
    if (!isUserFolderTab(id)) return;
    final numericId = int.tryParse(id.trim());
    if (numericId == null) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    await _api.sendDlgGrpDel(numericId);
    if (_activeTab == id) {
      _activeTab = BuiltinTab.all;
    }
    await refreshFolders();
  }

  /// Изменить порядок папок (`arr` без «Все»).
  Future<void> sortFolders(List<String> arr) async {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    await _api.sendDlgGrpSort(arr);
    _applyFolderSortOrder(arr);
    notifyListeners();
  }

  /// Собрать `arr` для `dlg_grp_sort` из упорядоченных вкладок.
  List<String> buildFolderSortPayload(
    List<({String id, String label, bool canReorder})> ordered,
  ) {
    final arr = <String>[];
    var i = 0;
    for (final item in ordered) {
      i++;
      if (i <= 1) continue;
      final sortId = BuiltinTab.sortId(item.id);
      if (sortId != null) arr.add(sortId);
    }
    return arr;
  }

  void _applyFolderSortOrder(List<String> arr) {
    final userIds = arr
        .where((id) => id != '2' && id != '3')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final byId = {for (final g in _groups) g.id: g};
    _groups = [
      for (final id in userIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  int? badgeForTab(String tabId) {
    if (tabId == BuiltinTab.ai) {
      final c = _dialogs.where((d) => (d.ai ?? 0) > 0).fold<int>(
            0,
            (a, d) => a + d.unread,
          );
      return c > 0 ? c : null;
    }
    return null;
  }

  /// Все диалоги без фильтров вкладки/поиска (для окна пересылки).
  List<DialogsListViewModel> get allDialogs => List.unmodifiable(_dialogs);

  Iterable<DialogsListViewModel> _dialogsForActiveTab() {
    Iterable<DialogsListViewModel> list = _dialogs;

    if (_activeTab == BuiltinTab.archive) {
      list = list.where((d) => isDialogArchived(d.id));
    } else {
      list = list.where((d) => !isDialogArchived(d.id));
    }

    if (_activeTab == BuiltinTab.ai) {
      list = list.where((d) => (d.ai ?? 0) > 0);
    } else if (_activeTab == BuiltinTab.personal) {
      list = list.where((d) => !d.isGrp);
    } else if (_activeTab != BuiltinTab.all &&
        _activeTab != BuiltinTab.archive) {
      final group = _groups.where((g) => g.id == _activeTab).firstOrNull;
      if (group == null) {
        list = const [];
      } else {
        final ids = group.dialogIds;
        if (ids.isEmpty) {
          list = const [];
        } else {
          list = list.where((d) => d.id != null && ids.contains(d.id));
        }
      }
    }
    return list;
  }

  List<DialogsListViewModel> get dialogs {
    var list = _dialogsForActiveTab().toList();

    if (_globalSearchRibbonVisible &&
        _globalSearchScope == GlobalSearchScope.chats &&
        _search.trim().isNotEmpty) {
      list = GlobalSearch.filterChats(list, _search);
    } else if (_search.trim().isNotEmpty && !_globalSearchRibbonVisible) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (d) =>
                d.chatName.toLowerCase().contains(q) ||
                d.last_msg.toLowerCase().contains(q),
          )
          .toList();
    }

    // Порядок как у сервера / после _bumpDialog. Пины стабильно сверху,
    // внутри группы относительный порядок не меняем (List.sort нестабилен).
    final pinned = <DialogsListViewModel>[];
    final rest = <DialogsListViewModel>[];
    for (final d in list) {
      (d.isPinned ? pinned : rest).add(d);
    }
    return [...pinned, ...rest];
  }

  String? get selectedId => _selectedId;

  DialogsListViewModel? get selectedDialog {
    if (_selectedId == null) return null;
    for (final d in _dialogs) {
      if (_sameDlgId(d.id, _selectedId)) return d;
    }
    return null;
  }

  /// Личные контакты для «Написать сообщение» (есть `usr_id`, не группы).
  List<DialogsListViewModel> get privateContactsForNewMessage {
    final myId = _profile?.id.trim() ?? '';
    final list = _dialogs.where((d) {
      if (d.isGrp || d.fav) return false;
      final uid = d.usr_id?.trim() ?? '';
      if (uid.isEmpty) return false;
      if (myId.isNotEmpty && ReactionUtils.sameUserId(uid, myId)) return false;
      return true;
    }).toList();
    list.sort(
      (a, b) => a.chatName.toLowerCase().compareTo(b.chatName.toLowerCase()),
    );
    return list;
  }

  /// Открыть личный чат с пользователем. Если чата нет — `dlg_id = "0"`.
  Future<void> openPrivateChatWithUser({
    required String usrId,
    String name = '',
    String avatar = '',
    String? phone,
    List<String>? avatarColor,
  }) async {
    final uid = usrId.trim();
    if (uid.isEmpty) return;

    final existing = _findPrivateDialogByUsrId(uid, allowPlaceholder: false);
    if (existing != null) {
      await selectDialog(existing.id);
      return;
    }

    final draft = _findPrivateDialogByUsrId(uid, allowPlaceholder: true);
    if (draft != null && draft.isNewContactWithoutDialog) {
      if (name.trim().isNotEmpty) draft.chatName = name.trim();
      await selectDialog(draft.id ?? '0');
      return;
    }

    // Один локальный черновик `"0"` за раз.
    _dialogs.removeWhere(
      (d) =>
          d.isNewContactWithoutDialog &&
          !ReactionUtils.sameUserId(d.usr_id ?? '', uid),
    );

    final dialog = DialogsListViewModel(
      id: '0',
      usr_id: uid,
      chatName: name.trim().isNotEmpty ? name.trim() : uid,
      avatar: avatar,
      avatarColor: avatarColor,
      phone: phone,
      chatType: ChatType.privateChat,
      isGrp: false,
    );
    _dialogs.insert(0, dialog);
    await selectDialog('0');
  }

  /// Открыть контакт из списка «Написать сообщение».
  Future<void> openDialogFromContact(DialogsListViewModel contact) async {
    final uid = contact.usr_id?.trim() ?? '';
    if (uid.isEmpty) return;

    if (!DialogsListViewModel.isPlaceholderDlgId(contact.id)) {
      await selectDialog(contact.id);
      return;
    }

    await openPrivateChatWithUser(
      usrId: uid,
      name: contact.chatName,
      avatar: contact.avatar,
      phone: contact.phone,
      avatarColor: contact.avatarColor,
    );
  }

  DialogsListViewModel? _findPrivateDialogByUsrId(
    String usrId, {
    required bool allowPlaceholder,
  }) {
    for (final d in _dialogs) {
      if (d.isGrp || d.fav) continue;
      if (!ReactionUtils.sameUserId(d.usr_id ?? '', usrId)) continue;
      final placeholder = DialogsListViewModel.isPlaceholderDlgId(d.id);
      if (allowPlaceholder) {
        if (placeholder) return d;
      } else {
        if (!placeholder) return d;
      }
    }
    return null;
  }

  /// Поля адресата исходящего `msg`: `to_id` или `dlg_id`.
  void _applyMsgTarget(
    Map<String, dynamic> payload,
    DialogsListViewModel dialog,
  ) {
    if (dialog.isNewContactWithoutDialog) {
      final toId = dialog.usr_id?.trim() ?? '';
      if (toId.isNotEmpty) payload['to_id'] = toId;
      return;
    }
    final dlgId = dialog.id?.trim() ?? '';
    if (dlgId.isNotEmpty) payload['dlg_id'] = dlgId;
  }

  Future<void> selectDialog(
    String? id, {
    bool closeGlobalSearch = true,
  }) async {
    if (closeGlobalSearch) closeGlobalSearchRibbon();

    if (_selectedId == id) return;
    if (_selectedId != null &&
        id != null &&
        _sameDlgId(_selectedId, id)) {
      return;
    }

    final previousId = _selectedId;
    if (previousId != null &&
        (id == null || !dlgIdsEqual(previousId, id))) {
      _saveComposerDraft(previousId, _composerText);
      flushComposerTyping(dlgId: previousId, text: _composerText);
    }
    _clearChatTypingIndicator();
    _composerText = '';
    _pendingComposerDraft = null;
    _pendingComposerDraftDlgId = null;

    _flushChatScroll(_selectedId);
    _replyToMessage = null;
    _editingMessage = null;
    _selectedId = id;
    _messagesError = null;
    final d = selectedDialog;
    if (d != null && d.unread > 0) d.unread = 0;

    // Подставить локальный черновик в инпут при открытии чата.
    if (id != null && !DialogsListViewModel.isPlaceholderDlgId(id)) {
      final local = composerDraftPreview(id);
      if (local != null) {
        _pendingComposerDraft = _composerDrafts[_draftMapKey(id)] ?? local;
        _pendingComposerDraftDlgId = id;
      }
      _composerDraftEpoch++;
    }

    if (id == null) {
      notifyListeners();
      return;
    }

    // Новый контакт без диалога — без msg_list / dlg_info / typing draft.
    if (DialogsListViewModel.isPlaceholderDlgId(id) ||
        (d?.isNewContactWithoutDialog ?? false)) {
      notifyListeners();
      return;
    }

    // Хвост только при первом открытии в сессии. Повторный вход в тот же чат
    // не обрезает уже подгруженную историю — иначе сбивается позиция скролла.
    if (!_messagesLoadedFor.any((loaded) => _sameDlgId(loaded, id))) {
      trimDialogToLatestPage(id);
    }
    notifyListeners();

    if (_connectionStatus == ConnectionStatus.connected) {
      loadMessages(id);
      unawaited(_restoreTypingDraft(id));
      unawaited(_loadPinnedMessages(id));
    } else {
      await _restoreMessagesFromCache(id);
      trimDialogToLatestPage(id);
      _messagesLoadedFor.add(id.trim());
      if (_sameDlgId(_selectedId, id)) notifyListeners();
    }

    // Повторный flush предыдущего чата после notify — на случай позднего commit.
    if (previousId != null && !dlgIdsEqual(previousId, id)) {
      _flushChatScroll(previousId);
    }
  }

  /// Загрузить сообщения диалога (`msg_list`).
  ///
  /// Как Forum_ios / WS_MSG_LIST:
  /// - кэш пуст → `first_id: "0"` (хвост истории);
  /// - кэш есть → `last_id` + `last_dt` (только новые после последнего).
  Future<void> loadMessages(String dlgId, {bool force = false}) {
    if (DialogsListViewModel.isPlaceholderDlgId(dlgId)) {
      return Future.value();
    }
    // Повторное открытие в сессии — только getNew (новые после last_id).
    if (!force &&
        _messagesLoadedFor.any((id) => _sameDlgId(id, dlgId))) {
      return _syncNewerMessages(dlgId);
    }

    final existing = _messageLoadsInFlight[dlgId];
    if (!force && existing != null) return existing;

    final future = _loadMessagesImpl(dlgId, force: force);
    _messageLoadsInFlight[dlgId] = future;
    return future.whenComplete(() => _messageLoadsInFlight.remove(dlgId));
  }

  Future<void> _loadMessagesImpl(String dlgId, {bool force = false}) async {
    final gen = ++_loadGeneration;
    final dialog = _findDialog(dlgId);

    if (force) {
      _msgHasMore.remove(dlgId);
      _messagesLoadedFor.removeWhere((id) => _sameDlgId(id, dlgId));
      if (dialog != null) dialog.messages = [];
    }

    await _ensureDeletedMessageIdsLoaded(dlgId);

    // Как iOS JsonStorage: сначала локальный кэш, потом выбор режима.
    if (dialog != null && dialog.messages.isEmpty) {
      await _restoreMessagesFromCache(dlgId);
      trimDialogToLatestPage(dlgId);
    }

    final request =
        force ? MsgListRequest.initial() : _buildMsgListRequest(dialog);
    final replace = !request.getNew;

    // Пустой кэш / force — ждём хвост; при getNew ленту из кэша показываем сразу.
    if (replace) {
      _messagesLoading = true;
      _messagesError = null;
      notifyListeners();
    } else if (dialog != null && dialog.messages.isNotEmpty) {
      _messagesLoadedFor.add(dlgId.trim());
      _messagesError = null;
      notifyListeners();
    }

    try {
      final result = await _api.fetchMessageList(
        dlgId,
        request: request,
        currentUserId: _profile?.id,
        currentUserName: _reactionAuthorName,
        isGroupChat: dialog?.isGrp ?? false,
      );

      if (gen != _loadGeneration || !_sameDlgId(_selectedId, dlgId)) return;

      if (dialog != null) {
        final filtered = MsgListResult(
          messages: _withoutDeletedMessages(dlgId, result.messages),
          isHistory: result.isHistory,
          responseFirstId: result.responseFirstId,
          hasMoreHistory: result.hasMoreHistory,
        );
        MsgListMerge.apply(
          dialog: dialog,
          result: filtered,
          replace: replace,
          onHistoryPagination: (hasMore) => _msgHasMore[dlgId] = hasMore,
        );
        _filterDeletedMessagesInDialog(dialog);
        final deleted = _deletedMessageIds[dlgId];
        if (deleted != null && deleted.isNotEmpty && !request.getNew) {
          unawaited(
            ForumCache.instance.removeMessagesFromCache(dlgId, deleted),
          );
        }
        if (dialog.messages.isNotEmpty) {
          _updateDialogPreview(dialog, dialog.messages.last);
        }
        _messagesLoadedFor.add(dlgId.trim());
        _messagesError = null;
        if (_sameDlgId(_selectedId, dlgId)) {
          _sendReadStatus(dialog, dlgId);
        }
      }
    } on ForumApiException catch (e) {
      if (gen == _loadGeneration && _sameDlgId(_selectedId, dlgId)) {
        await _showCachedMessagesOrError(dialog, dlgId, e.message);
      }
    } catch (e) {
      if (gen == _loadGeneration && _sameDlgId(_selectedId, dlgId)) {
        await _showCachedMessagesOrError(dialog, dlgId, e.toString());
      }
    } finally {
      if (gen == _loadGeneration && _sameDlgId(_selectedId, dlgId)) {
        _messagesLoading = false;
        notifyListeners();
      }
    }
  }

  /// Догрузка только новых сообщений (`last_id` / `last_dt`), как iOS getNew.
  Future<void> _syncNewerMessages(String dlgId) async {
    final dialog = _findDialog(dlgId);
    if (dialog == null) return;
    final request = _buildMsgListRequest(dialog);
    if (!request.getNew) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    final key = 'newer:$dlgId';
    final existing = _messageLoadsInFlight[key];
    if (existing != null) return existing;

    final future = () async {
      try {
        final result = await _api.fetchMessageList(
          dlgId,
          request: request,
          currentUserId: _profile?.id,
          currentUserName: _reactionAuthorName,
          isGroupChat: dialog.isGrp,
        );
        if (!_sameDlgId(_selectedId, dlgId)) return;

        final filtered = MsgListResult(
          messages: _withoutDeletedMessages(dlgId, result.messages),
          isHistory: result.isHistory,
          responseFirstId: result.responseFirstId,
          hasMoreHistory: result.hasMoreHistory,
        );
        MsgListMerge.apply(
          dialog: dialog,
          result: filtered,
          replace: false,
          onHistoryPagination: (hasMore) => _msgHasMore[dlgId] = hasMore,
        );
        _filterDeletedMessagesInDialog(dialog);
        if (dialog.messages.isNotEmpty) {
          _updateDialogPreview(dialog, dialog.messages.last);
        }
        if (_sameDlgId(_selectedId, dlgId)) {
          _sendReadStatus(dialog, dlgId);
        }
        notifyListeners();
      } catch (_) {}
    }();

    _messageLoadsInFlight[key] = future;
    return future.whenComplete(() => _messageLoadsInFlight.remove(key));
  }

  Future<void> _showCachedMessagesOrError(
    DialogsListViewModel? dialog,
    String dlgId,
    String error,
  ) async {
    if (dialog == null) {
      _messagesError = error;
      _messagesLoadedFor.add(dlgId.trim());
      return;
    }
    if (dialog.messages.isEmpty) {
      await _restoreMessagesFromCache(dlgId);
    }
    if (dialog.messages.isEmpty) {
      _messagesError = error;
    } else {
      trimDialogToLatestPage(dlgId);
    }
    _messagesLoadedFor.add(dlgId.trim());
  }

  /// Курсор msg_list: при наличии локальных сообщений — getNew (`last_id`+`last_dt`).
  MsgListRequest _buildMsgListRequest(DialogsListViewModel? dialog) {
    if (dialog != null && dialog.messages.isNotEmpty) {
      final last = MsgListCursors.lastSaved(dialog.messages);
      if (last != null) {
        return MsgListRequest.newer(
          lastId: last.id,
          lastDt: MsgListCursors.lastDt(last),
        );
      }
    }
    return MsgListRequest.initial();
  }

  /// Подгрузить более старые сообщения (first_id).
  Future<void> loadOlderMessages(String dlgId) async {
    if (_messagesLoadingOlder) return;
    if (!(_msgHasMore[dlgId] ?? false)) return;
    if (_selectedId != dlgId) return;

    final dialog = _dialogs.where((d) => d.id == dlgId).firstOrNull;
    if (dialog == null) return;

    _messagesLoadingOlder = true;
    notifyListeners();

    try {
      await _loadOlderMessagesPage(dlgId, dialog);
    } on ForumApiException catch (e) {
      if (_selectedId == dlgId) _messagesError = e.message;
    } catch (e) {
      if (_selectedId == dlgId) _messagesError = e.toString();
    } finally {
      _messagesLoadingOlder = false;
      notifyListeners();
    }
  }

  Future<void> _loadOlderMessagesPage(
    String dlgId,
    DialogsListViewModel dialog,
  ) async {
    final existing = _olderMessageLoadsInFlight[dlgId];
    if (existing != null) {
      await existing;
      return;
    }

    final future = _loadOlderMessagesPageImpl(dlgId, dialog);
    _olderMessageLoadsInFlight[dlgId] = future;
    try {
      await future;
    } finally {
      _olderMessageLoadsInFlight.remove(dlgId);
    }
  }

  Future<void> _loadOlderMessagesPageImpl(
    String dlgId,
    DialogsListViewModel dialog,
  ) async {
    if (!(_msgHasMore[dlgId] ?? false)) return;

    final oldest = MsgListCursors.firstSaved(dialog.messages);
    if (oldest == null) {
      _msgHasMore[dlgId] = false;
      return;
    }

    final result = await _api.fetchMessageList(
      dlgId,
      request: MsgListRequest.history(oldest.id),
      currentUserId: _profile?.id,
      currentUserName: _reactionAuthorName,
      isGroupChat: dialog.isGrp,
    );

    if (result.messages.isEmpty) {
      _msgHasMore[dlgId] = false;
      return;
    }

    final filtered = MsgListResult(
      messages: _withoutDeletedMessages(dlgId, result.messages),
      isHistory: result.isHistory,
      responseFirstId: result.responseFirstId,
      hasMoreHistory: result.hasMoreHistory,
    );
    MsgListMerge.apply(
      dialog: dialog,
      result: filtered,
      onHistoryPagination: (hasMore) => _msgHasMore[dlgId] = hasMore,
    );
    _filterDeletedMessagesInDialog(dialog);
    final deleted = _deletedMessageIds[dlgId];
    if (deleted != null && deleted.isNotEmpty) {
      unawaited(
        ForumCache.instance.removeMessagesFromCache(dlgId, deleted),
      );
    }
  }

  void clearSelection() {
    if (_selectedId != null) {
      _saveComposerDraft(_selectedId, _composerText);
      flushComposerTyping(dlgId: _selectedId!, text: _composerText);
    }
    _clearChatTypingIndicator();
    _composerText = '';
    _pendingComposerDraft = null;
    _pendingComposerDraftDlgId = null;
    _flushChatScroll(_selectedId);
    _replyToMessage = null;
    _editingMessage = null;
    _selectedId = null;
    notifyListeners();
  }

  /// Текст черновика для превью в списке чатов (как Telegram «Draft:»).
  String? composerDraftPreview(String? dlgId) {
    final key = _draftMapKey(dlgId);
    if (key == null) return null;
    // Канонический id из карты (учитываем _sameDlgId).
    for (final entry in _composerDrafts.entries) {
      if (_sameDlgId(entry.key, key)) {
        final t = entry.value.trim();
        return t.isEmpty ? null : t;
      }
    }
    return null;
  }

  String? _draftMapKey(String? dlgId) {
    final key = dlgId?.trim() ?? '';
    if (key.isEmpty || DialogsListViewModel.isPlaceholderDlgId(key)) {
      return null;
    }
    return key;
  }

  void _saveComposerDraft(String? dlgId, String text) {
    final key = _draftMapKey(dlgId);
    if (key == null) return;
    // Удалить прежние ключи того же диалога.
    _composerDrafts.removeWhere((k, _) => _sameDlgId(k, key));
    if (text.trim().isEmpty) return;
    _composerDrafts[key] = text;
  }

  void _clearComposerDraft(String? dlgId) {
    final key = _draftMapKey(dlgId);
    if (key == null) return;
    final before = _composerDrafts.length;
    _composerDrafts.removeWhere((k, _) => _sameDlgId(k, key));
    if (_composerDrafts.length != before) {
      // Список чатов должен убрать «Черновик:».
      notifyListeners();
    }
  }

  /// Обновление текста инпута → WS `typing` (throttle 1.5 с).
  void reportComposerText(String text) {
    _composerText = text;
    final dlgId = _selectedId?.trim();
    if (dlgId == null || dlgId.isEmpty || dlgId == '0') return;
    // Пустой инпут — сразу убрать черновик из списка (после отправки / очистки).
    if (text.trim().isEmpty) {
      _clearComposerDraft(dlgId);
    }
    _sendTyping(dlgId: dlgId, body: text, force: false);
  }

  /// Финальный flush черновика (выход из чата / смена диалога).
  void flushComposerTyping({String? dlgId, String? text}) {
    final id = (dlgId ?? _selectedId)?.trim();
    if (text != null) _composerText = text;
    if (id == null || id.isEmpty || id == '0') return;
    _saveComposerDraft(id, text ?? _composerText);
    _sendTyping(dlgId: id, body: text ?? _composerText, force: true);
  }

  /// Забрать черновик для подстановки в инпут (сервер или локальный).
  String? takeComposerDraft(String dlgId) {
    if (_pendingComposerDraftDlgId != null &&
        _sameDlgId(_pendingComposerDraftDlgId, dlgId)) {
      final draft = _pendingComposerDraft;
      _pendingComposerDraft = null;
      _pendingComposerDraftDlgId = null;
      if (draft != null && draft.trim().isNotEmpty) {
        _saveComposerDraft(dlgId, draft);
        return draft;
      }
    }
    return composerDraftPreview(dlgId);
  }

  void _sendTyping({
    required String dlgId,
    required String body,
    required bool force,
  }) {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastTypingSentAt != null &&
        now.difference(_lastTypingSentAt!) < _typingThrottle) {
      return;
    }
    _lastTypingSentAt = now;
    _api.sendTyping(dlgId: dlgId, body: body);
  }

  Future<void> _restoreTypingDraft(String dlgId) async {
    final usrId = _profile?.id.trim() ?? '';
    if (usrId.isEmpty) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    try {
      final draft = await _api.fetchOwnTypingDraft(
        dlgId: dlgId,
        currentUserId: usrId,
      );
      if (_selectedId != dlgId) return;
      final text = draft?.trim() ?? '';
      if (text.isEmpty) return;

      // Не перезаписываем, если пользователь уже начал печатать.
      if (_composerText.trim().isNotEmpty) return;

      _saveComposerDraft(dlgId, draft!);
      _pendingComposerDraft = draft;
      _pendingComposerDraftDlgId = dlgId;
      _composerDraftEpoch++;
      notifyListeners();
    } catch (_) {}
  }

  void _onTypingPush(Map<String, dynamic> map) {
    final dlgId = map['dlg_id']?.toString().trim() ?? '';
    if (dlgId.isEmpty) return;

    final frId = map['fr_id']?.toString().trim() ?? '';
    final myId = _profile?.id.trim() ?? '';
    if (myId.isNotEmpty && ReactionUtils.sameUserId(frId, myId)) return;

    final name = map['name']?.toString().trim() ?? '';
    final dialog = _findDialog(dlgId);
    final isGroup = dialog?.isGrp == true;
    final label = isGroup
        ? (name.isNotEmpty ? '$name печатает...' : 'печатает...')
        : 'печатает...';

    if (_sameDlgId(_selectedId, dlgId)) {
      _chatTypingLabel = label;
      _chatTypingTimer?.cancel();
      _chatTypingTimer = Timer(_typingIndicatorTtl, () {
        if (_chatTypingLabel == label) {
          _chatTypingLabel = null;
          notifyListeners();
        }
      });
      notifyListeners();
    }

    if (dialog == null) return;

    if (!_typingSavedLastMsg.containsKey(dlgId)) {
      _typingSavedLastMsg[dlgId] = dialog.last_msg;
    }
    _typingListPreview[dlgId] = label;
    dialog.last_msg = label;
    _typingListTimers[dlgId]?.cancel();
    _typingListTimers[dlgId] = Timer(_typingIndicatorTtl, () {
      final d = _findDialog(dlgId);
      final saved = _typingSavedLastMsg.remove(dlgId);
      _typingListPreview.remove(dlgId);
      _typingListTimers.remove(dlgId);
      if (d != null && saved != null && d.last_msg == label) {
        d.last_msg = saved;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> _loadPinnedMessages(String dlgId) async {
    try {
      final ids = await _api.fetchPinnedMessageIds(
        dlgId,
        usrId: _profile?.id ?? '',
      );
      _pinnedMsgIds[dlgId.trim()] = ids.toSet();
      if (_sameDlgId(_selectedId, dlgId)) notifyListeners();
    } catch (_) {}
  }

  void _onPinMsgPush(Map<String, dynamic> map) {
    final type = map['type']?.toString() ?? '';
    final data = map['data'];
    // iOS: grp_id на верхнем уровне; data — массив сообщений.
    final dlgId = (map['grp_id'] ??
                map['dlg_id'] ??
                (data is Map ? (data['dlg_id'] ?? data['grp_id']) : null))
            ?.toString()
            .trim() ??
        '';
    if (dlgId.isEmpty) return;

    final idsFromList = <String>{};
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final id = item['id']?.toString().trim() ??
              item['msg_id']?.toString().trim() ??
              '';
          if (id.isNotEmpty) idsFromList.add(id);
        }
      }
      _pinnedMsgIds[dlgId] = idsFromList;
      notifyListeners();
      return;
    }

    final set = _pinnedMsgIds.putIfAbsent(dlgId, () => <String>{});
    final dataMap = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final msgId =
        (dataMap['msg_id'] ?? dataMap['id'] ?? map['msg_id'])?.toString().trim() ??
            '';
    if (msgId.isEmpty) return;
    if (type.contains('del')) {
      set.remove(msgId);
    } else {
      set.add(msgId);
    }
    notifyListeners();
  }

  void _clearChatTypingIndicator() {
    _chatTypingTimer?.cancel();
    _chatTypingTimer = null;
    _chatTypingLabel = null;
  }

  String _nowTime() {
    final now = TimeOfDay.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  void _onMsgPush(Map<String, dynamic> data) {
    final msgs = data['msgs'];
    if (msgs is List && msgs.isNotEmpty) {
      _onMsgListPush(data);
      return;
    }

    // Не обновлять список по событиям с dlg_id == "0".
    final rawDlgId = _extractDlgId(data);
    if (rawDlgId != null &&
        DialogsListViewModel.isPlaceholderDlgId(rawDlgId)) {
      return;
    }

    final message = MessageMapper.fromServerJson(
      data,
      currentUserId: _profile?.id,
      currentUserName: _reactionAuthorName,
    );

    // Новый контакт: эхо с реальным dlg_id стыкуем по hash первого локального msg.
    final adopted = _adoptNewContactDialogIfNeeded(data, message);
    final msgDlgId = adopted ?? rawDlgId;
    if (msgDlgId == null ||
        DialogsListViewModel.isPlaceholderDlgId(msgDlgId)) {
      return;
    }

    final dialog = _findDialog(msgDlgId);
    if (dialog == null) {
      _enqueueUnknownDialogPush(
        msgDlgId,
        _PendingUnknownDialogPush.single(data, message),
      );
      return;
    }

    _applySingleMessage(dialog, msgDlgId, message);
  }

  void _onMsgListPush(Map<String, dynamic> data) {
    final msgDlgId = _extractDlgId(data);
    if (msgDlgId == null) return;

    final dialog = _findDialog(msgDlgId);
    if (dialog == null) {
      _enqueueUnknownDialogPush(
        msgDlgId,
        _PendingUnknownDialogPush.list(data),
      );
      return;
    }

    _applyMsgListPushToDialog(dialog, msgDlgId, data);
  }

  /// Push `dlg` без нашего запроса — новая группа, куда нас добавили.
  void _onDlgCreatedPush(Map<String, dynamic> resp) {
    if (resp['success'] == false) return;
    final created = _api.parseCreatedDialogResponse(
      resp,
      currentUserId: _profile?.id,
    );
    if (created == null) {
      // Карточки нет — подтянем полный список.
      unawaited(_refreshDialogsForUnknown(null));
      return;
    }
    final id = created.id?.trim() ?? '';
    if (id.isEmpty || DialogsListViewModel.isPlaceholderDlgId(id)) return;

    _upsertDialog(created);
    _bumpDialog(id);
    notifyListeners();
    ApiLogger.instance.logEvent('DLG', 'push новая группа dlg_id=$id');
    unawaited(_flushPendingUnknownDialogPushes(id));
    // На всякий случай синхронизируем полный список.
    unawaited(_refreshDialogsForUnknown(id));
  }

  void _enqueueUnknownDialogPush(
    String dlgId,
    _PendingUnknownDialogPush push,
  ) {
    ApiLogger.instance.logEvent(
      'MSG',
      'диалог не найден, ждём dlg_list: $dlgId',
    );
    (_pendingUnknownDialogPushes[dlgId] ??= []).add(push);
    unawaited(_refreshDialogsForUnknown(dlgId));
  }

  Future<void> _refreshDialogsForUnknown(String? dlgId) async {
    final key = dlgId?.trim() ?? '';
    if (key.isNotEmpty) _unknownDialogRefreshQueued.add(key);

    final inFlight = _unknownDialogRefreshInFlight;
    if (inFlight != null) {
      await inFlight;
      if (key.isEmpty) return;
      if (_findDialog(key) != null) {
        await _flushPendingUnknownDialogPushes(key);
        return;
      }
      // Первый refresh мог стартовать до появления чата на сервере —
      // ещё одна попытка (лимит в _runUnknownDialogRefresh).
      if (_pendingUnknownDialogPushes.containsKey(key) &&
          (_unknownDialogRefreshAttempts[key] ?? 0) < 3) {
        await _refreshDialogsForUnknown(key);
      }
      return;
    }

    final future = _runUnknownDialogRefresh();
    _unknownDialogRefreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_unknownDialogRefreshInFlight, future)) {
        _unknownDialogRefreshInFlight = null;
      }
    }
  }

  Future<void> _runUnknownDialogRefresh() async {
    final ids = <String>{
      ..._unknownDialogRefreshQueued,
      ..._pendingUnknownDialogPushes.keys,
    };
    _unknownDialogRefreshQueued.clear();
    if (ids.isEmpty) return;

    for (final id in ids) {
      _unknownDialogRefreshAttempts[id] =
          (_unknownDialogRefreshAttempts[id] ?? 0) + 1;
    }

    try {
      await refreshDialogs();
    } catch (_) {}

    for (final id in ids) {
      if (_findDialog(id) != null) {
        _unknownDialogRefreshAttempts.remove(id);
        await _flushPendingUnknownDialogPushes(id);
      } else {
        ApiLogger.instance.logEvent(
          'MSG',
          'диалог всё ещё не в dlg_list: $id '
          '(попытка ${_unknownDialogRefreshAttempts[id]})',
        );
      }
    }
  }

  Future<void> _flushPendingUnknownDialogPushes(String dlgId) async {
    final pending = _pendingUnknownDialogPushes.remove(dlgId);
    if (pending == null || pending.isEmpty) return;
    final dialog = _findDialog(dlgId);
    if (dialog == null) {
      _pendingUnknownDialogPushes[dlgId] = pending;
      return;
    }
    _unknownDialogRefreshAttempts.remove(dlgId);
    for (final push in pending) {
      if (push.listData != null) {
        _applyMsgListPushToDialog(dialog, dlgId, push.listData!);
      } else if (push.message != null) {
        _applySingleMessage(dialog, dlgId, push.message!);
      }
    }
  }

  void _applyMsgListPushToDialog(
    DialogsListViewModel dialog,
    String msgDlgId,
    Map<String, dynamic> data,
  ) {
    final raw = data['msgs'];
    if (raw is! List || raw.isEmpty) return;

    try {
      final result = _api.parseMsgListResponse(
        {'success': true, 'data': data},
        expectedDlgId: msgDlgId,
        currentUserId: _profile?.id,
        currentUserName: _reactionAuthorName,
        isGroupChat: dialog.isGrp,
      );
      _mergeMsgListResult(dialog, msgDlgId, result);
    } catch (e) {
      ApiLogger.instance.logEvent('MSG_LIST', 'ошибка push: $e');
    }
  }

  /// Если открыт / есть черновик `dlg_id=0` и hash совпал — назначить реальный id.
  /// Возвращает новый `dlg_id` или null.
  String? _adoptNewContactDialogIfNeeded(
    Map<String, dynamic> data,
    MessageViewModel message,
  ) {
    final newDlgId = _extractDlgId(data);
    if (newDlgId == null ||
        DialogsListViewModel.isPlaceholderDlgId(newDlgId)) {
      return null;
    }

    final hash = (data['hash']?.toString() ?? message.hash).trim();
    if (hash.isEmpty) return null;

    DialogsListViewModel? draft;
    final selected = selectedDialog;
    if (selected != null && selected.isNewContactWithoutDialog) {
      draft = selected;
    } else {
      draft = _dialogs.where((d) => d.isNewContactWithoutDialog).firstOrNull;
    }
    if (draft == null) return null;

    // Первое локальное сообщение (не date) должно совпасть по hash.
    MessageViewModel? firstLocal;
    for (final m in draft.messages) {
      if (m.type.toLowerCase() == 'date') continue;
      firstLocal = m;
      break;
    }
    if (firstLocal == null) return null;
    final localHash = firstLocal.hash.trim().isNotEmpty
        ? firstLocal.hash.trim()
        : firstLocal.id.trim();
    if (localHash.isEmpty || localHash != hash) {
      // Чужой msg при открытом `"0"` — игнорировать.
      if (selected != null && selected.isNewContactWithoutDialog) {
        ApiLogger.instance.logEvent(
          'MSG',
          'new contact: hash mismatch, ignore dlg=$newDlgId',
        );
      }
      return null;
    }

    _assignRealDialogId(draft, newDlgId);
    return newDlgId;
  }

  void _assignRealDialogId(DialogsListViewModel dialog, String newDlgId) {
    final oldId = (dialog.id ?? '0').trim();
    if (oldId == newDlgId.trim()) return;

    // Если уже есть диалог с этим id — сливаем сообщения и удаляем черновик.
    final existing = _findDialog(newDlgId);
    if (existing != null && !identical(existing, dialog)) {
      if (dialog.messages.isNotEmpty && existing.messages.isEmpty) {
        existing.messages = List.of(dialog.messages);
      }
      _dialogs.remove(dialog);
      if (_sameDlgId(_selectedId, oldId) || _selectedId == '0') {
        _selectedId = existing.id;
      }
      unawaited(ForumCache.instance.deleteMessagesFile(oldId));
      ApiLogger.instance.logEvent(
        'MSG',
        'assignRealDialogId merge $oldId → $newDlgId',
      );
      return;
    }

    dialog.id = newDlgId;
    if (_sameDlgId(_selectedId, oldId) || _selectedId == '0') {
      _selectedId = newDlgId;
    }

    if (_messagesLoadedFor.remove(oldId)) {
      _messagesLoadedFor.add(newDlgId);
    }
    final deleted = _deletedMessageIds.remove(oldId);
    if (deleted != null) {
      _deletedMessageIds[newDlgId] = deleted;
    }
    final readAck = _readAckSent.remove(oldId);
    if (readAck != null) {
      _readAckSent[newDlgId] = readAck;
    }
    final hasMore = _msgHasMore.remove(oldId);
    if (hasMore != null) {
      _msgHasMore[newDlgId] = hasMore;
    }

    unawaited(ForumCache.instance.migrateMessagesCache(oldId, newDlgId));
    ApiLogger.instance.logEvent('MSG', 'assignRealDialogId $oldId → $newDlgId');
  }

  String? _extractDlgId(Map<String, dynamic> data) {
    final id = data['dlg_id'] ??
        data['grp_id'] ??
        data['dialog_id'] ??
        data['dlgId'] ??
        data['grpId'];
    if (id == null) return null;
    final s = id.toString().trim();
    return s.isEmpty ? null : s;
  }

  DialogsListViewModel? _findDialog(String msgDlgId) {
    return _dialogs.where((d) => _sameDlgId(d.id, msgDlgId)).firstOrNull;
  }

  void _applySingleMessage(
    DialogsListViewModel dialog,
    String dlgId,
    MessageViewModel message,
  ) {
    final deleted = _deletedMessageIds[dlgId];
    if (deleted != null && _messageMatchesAnyDeletedId(message, deleted)) {
      return;
    }

    // Пока история чата не загружена — не сидируем messages одним push
    // (geotr live и т.п.), иначе первая msg_list уходит как newer и теряет хвост.
    // Превью в списке диалогов всё равно обновляем.
    if (!isDialogHistoryReady(dlgId) && dialog.messages.isEmpty) {
      _updateDialogPreview(dialog, message);
      _bumpDialog(dlgId);
      if (!_sameDlgId(_selectedId, dlgId) && !message.my) {
        dialog.unread++;
      }
      notifyListeners();
      return;
    }

    if (!MsgListMerge.applyIncoming(dialog: dialog, incoming: message)) {
      return;
    }

    dialog.messages = List<MessageViewModel>.from(dialog.messages);
    MessageMapper.applyGrouping(
      dialog.messages,
      isGroupChat: dialog.isGrp,
    );

    _updateDialogPreview(dialog, message);
    _bumpDialog(dlgId);

    final isOpen = _sameDlgId(_selectedId, dlgId);
    if (!isOpen && !message.my) {
      dialog.unread++;
    }
    if (isOpen && isDialogHistoryReady(dlgId) && !message.my) {
      _sendReadStatus(dialog, dlgId);
    }

    notifyListeners();
  }

  void _onMsgDelPush(Map<String, dynamic> map) {
    final dlgId = map['dlg_id']?.toString().trim() ??
        (map['data'] is Map
            ? map['data']['dlg_id']?.toString().trim()
            : null);
    if (dlgId == null || dlgId.isEmpty) return;

    final ids = _parseMsgDelIds(map);
    if (ids.isEmpty) return;

    final dialog = _findDialog(dlgId);
    if (dialog == null) return;

    if (_removeMessagesFromDialog(dialog, ids)) {
      notifyListeners();
    }
  }

  List<String> _parseMsgDelIds(Map<String, dynamic> map) {
    dynamic raw = map['ids'];
    if (raw == null && map['data'] is Map) {
      raw = (map['data'] as Map)['ids'];
    }
    if (raw == null) return const [];

    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return const [];
    if (text.contains(',')) {
      return text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [text];
  }

  bool _messageMatchesDeleteId(MessageViewModel message, String id) {
    final target = id.trim();
    if (target.isEmpty) return false;
    return message.id == target ||
        message.hash == target ||
        (message.id.isEmpty && message.hash == target);
  }

  bool _removeMessagesFromDialog(
    DialogsListViewModel dialog,
    Iterable<String> ids,
  ) {
    final idSet = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (idSet.isEmpty) return false;

    final dlgId = dialog.id?.trim() ?? '';

    // Запомним и hash, и id — чтобы кэш/сервер не вернули сообщение.
    final remembered = <String>{...idSet};
    for (final m in dialog.messages) {
      if (idSet.any((id) => _messageMatchesDeleteId(m, id))) {
        final mid = m.id.trim();
        final hash = m.hash.trim();
        if (mid.isNotEmpty) remembered.add(mid);
        if (hash.isNotEmpty) remembered.add(hash);
      }
    }

    final before = dialog.messages.length;
    dialog.messages.removeWhere(
      (m) => idSet.any((id) => _messageMatchesDeleteId(m, id)),
    );
    if (dialog.messages.length == before) return false;

    _clearReplyIfDeleted(idSet);
    _refreshDialogPreviewAfterDelete(dialog);
    dialog.messages = List<MessageViewModel>.from(dialog.messages);
    MessageMapper.applyGrouping(
      dialog.messages,
      isGroupChat: dialog.isGrp,
    );

    if (dlgId.isNotEmpty && remembered.isNotEmpty) {
      unawaited(_rememberDeletedMessages(dlgId, remembered));
    }
    return true;
  }

  void _clearReplyIfDeleted(Set<String> ids) {
    final reply = _replyToMessage;
    if (reply == null) return;
    if (ids.any((id) => _messageMatchesDeleteId(reply, id))) {
      _replyToMessage = null;
    }
  }

  void _refreshDialogPreviewAfterDelete(DialogsListViewModel dialog) {
    if (dialog.messages.isNotEmpty) {
      final last = dialog.messages.last;
      last.avaOnBottom = true;
      dialog.last_msg = _previewFor(last);
      dialog.last_msg_dttmcr = last.dtshow;
      dialog.last_msg_fr_name = last.fr_name;
      dialog.last_msg_status = last.my ? last.status : -2;
      dialog.last_msg_id = last.id;
      dialog.last_msg_fr_id = last.fr_id ?? '';
    } else {
      dialog.last_msg = '';
      dialog.last_msg_fr_name = '';
      dialog.last_msg_fr_id = '';
      dialog.last_msg_status = -2;
      dialog.last_msg_id = '';
    }
  }

  void _onStatusPush(Map<String, dynamic> data) {
    final toId = data['to_id']?.toString().trim() ?? '';
    final myId = (_profile?.id ?? '').trim();
    // WS_STATUS.md: игнорировать, если событие адресовано нам как получателю.
    if (toId.isNotEmpty && myId.isNotEmpty && toId == myId) return;

    final dlgId = data['dlg_id']?.toString();
    if (dlgId == null || dlgId.isEmpty) return;

    final status = _parseStatus(data['status']);
    final ids = _parseStatusIds(data['ids']?.toString() ?? '');
    if (ids.isEmpty) return;

    final dialog = _findDialog(dlgId);
    if (dialog == null) return;

    var changed = false;
    for (final m in dialog.messages) {
      if (ids.contains(m.id) && m.status != status) {
        m.status = status;
        changed = true;
      }
    }

    // DialogsList.onRecvStatus — превью последнего исходящего в списке чатов.
    if (myId.isNotEmpty &&
        dialog.last_msg_fr_id == myId &&
        dialog.last_msg_id.isNotEmpty &&
        ids.contains(dialog.last_msg_id)) {
      dialog.last_msg_status = status;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  /// Отправить `status: 2` для непрочитанных входящих (WS_STATUS.md).
  void _sendReadStatus(DialogsListViewModel dialog, String dlgId) {
    if (!_api.isConnected || _connectionStatus != ConnectionStatus.connected) {
      return;
    }

    final myId = (_profile?.id ?? '').trim();
    if (myId.isEmpty) return;

    final acked = _readAckSent.putIfAbsent(dlgId, () => <String>{});
    final unreadIds = <String>[];

    for (final m in dialog.messages) {
      if (m.my) continue;
      if (!MsgListCursors.isSavedMessage(m)) continue;
      if (acked.contains(m.id)) continue;
      unreadIds.add(m.id);
    }

    if (unreadIds.isEmpty) return;

    _api.sendStatus(
      status: 2,
      dlgId: dlgId,
      ids: unreadIds.join(','),
    );
    acked.addAll(unreadIds);
  }

  static int _parseStatus(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Set<String> _parseStatusIds(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  void _mergeMsgListResult(
    DialogsListViewModel dialog,
    String dlgId,
    MsgListResult result,
  ) {
    final filteredMessages = _withoutDeletedMessages(dlgId, result.messages);
    if (filteredMessages.isEmpty) return;

    final beforeCount = dialog.messages.length;
    final filtered = MsgListResult(
      messages: filteredMessages,
      isHistory: result.isHistory,
      responseFirstId: result.responseFirstId,
      hasMoreHistory: result.hasMoreHistory,
    );

    MsgListMerge.apply(
      dialog: dialog,
      result: filtered,
      onHistoryPagination: (hasMore) {
        if (result.isHistory) _msgHasMore[dlgId] = hasMore;
      },
    );
    _filterDeletedMessagesInDialog(dialog);
    dialog.messages = List<MessageViewModel>.from(dialog.messages);
    MessageMapper.applyGrouping(
      dialog.messages,
      isGroupChat: dialog.isGrp,
    );

    final added = dialog.messages.length - beforeCount;
    if (added <= 0 && !result.isHistory) {
      // Все сообщения уже были в списке (дедупликация).
      return;
    }

    _updateDialogPreview(dialog, filteredMessages.last);
    _bumpDialog(dlgId);

    final isOpen = _sameDlgId(_selectedId, dlgId);
    if (!isOpen && added > 0) {
      dialog.unread += added;
    }
    if (isOpen) {
      _messagesLoadedFor.add(dlgId);
      if (!result.isHistory) {
        _sendReadStatus(dialog, dlgId);
      }
    }

    notifyListeners();
  }

  /// Сохранить загруженные сообщения при обновлении списка диалогов.
  List<DialogsListViewModel> _mergePreservingMessages(
    List<DialogsListViewModel> incoming,
  ) {
    final oldById = <String, DialogsListViewModel>{
      for (final d in _dialogs)
        if (d.id != null && d.id!.isNotEmpty) d.id!: d,
    };
    for (final d in incoming) {
      final id = d.id;
      if (id == null) continue;
      final old = oldById[id];
      if (old != null && old.messages.isNotEmpty) {
        d.messages = List<MessageViewModel>.from(old.messages);
      }
      if (old != null && old.chatMuted) {
        d.chatMuted = true;
      }
    }
    _applyLocalDialogPrefs(incoming);

    // Локальные черновики dlg_id=0 не теряем при refresh dlg_list.
    for (final draft in _dialogs.where((d) => d.isNewContactWithoutDialog)) {
      final uid = draft.usr_id?.trim() ?? '';
      if (uid.isEmpty) continue;
      final hasReal = incoming.any(
        (d) =>
            !d.isGrp &&
            !DialogsListViewModel.isPlaceholderDlgId(d.id) &&
            ReactionUtils.sameUserId(d.usr_id ?? '', uid),
      );
      if (hasReal) continue;
      final already = incoming.any(
        (d) =>
            d.isNewContactWithoutDialog &&
            ReactionUtils.sameUserId(d.usr_id ?? '', uid),
      );
      if (!already) incoming.insert(0, draft);
    }

    return incoming;
  }

  void _scheduleReconnect() {
    if (!_isAuthenticated) return;
    if (_reconnectPending) return;
    _reconnectPending = true;
    _stopDialogsLiveSync();
    _connectionStatus = ConnectionStatus.error;
    _connectionError = 'Соединение потеряно. Переподключение…';
    notifyListeners();

    Future<void>.delayed(const Duration(seconds: 2), () async {
      _reconnectPending = false;
      if (!_isAuthenticated || _api.isConnected) return;
      try {
        final uid = await DeviceIdService.getOrCreate();
        await _api.connect();
        _profile = await _api.login(
          uid,
          fcmToken: FirebaseService.instance.fcmToken,
        );
        _connectionStatus = ConnectionStatus.connected;
        _connectionError = null;
        notifyListeners();
        _startDialogsLiveSync();
        unawaited(refreshDialogs());
        unawaited(_resendPendingMessages());
        final openId = _selectedId;
        if (openId != null &&
            !DialogsListViewModel.isPlaceholderDlgId(openId)) {
          loadMessages(openId, force: true);
        }
      } catch (e) {
        _connectionError = e.toString();
        notifyListeners();
        _scheduleReconnect();
      }
    });
  }

  /// Сравнение dlg_id (строка / число).
  static bool sameDlgId(String? a, String? b) => _sameDlgId(a, b);

  Future<void> _loadDialogLocalPrefs() async {
    final loaded = await DialogLocalPrefs.load();
    _mutedUntil
      ..clear()
      ..addAll(loaded.mutedUntil);
    _archivedIds
      ..clear()
      ..addAll(loaded.archived);
    _applyLocalDialogPrefs(_dialogs);
    _scheduleMuteExpiry();
  }

  Future<void> _saveDialogLocalPrefs() {
    return DialogLocalPrefs.save(
      mutedUntil: Map<String, int>.from(_mutedUntil),
      archived: Set<String>.from(_archivedIds),
    );
  }

  void _applyLocalDialogPrefs(List<DialogsListViewModel> list) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = <String>[];
    for (final d in list) {
      final until = _prefValue(_mutedUntil, d.id);
      if (until == null) continue;
      if (until != 0 && until <= now) {
        expired.add(d.id ?? '');
        d.chatMuted = false;
      } else {
        d.chatMuted = true;
      }
    }
    for (final id in expired) {
      if (id.isNotEmpty) _removePrefKey(_mutedUntil, id);
    }
    if (expired.isNotEmpty) unawaited(_saveDialogLocalPrefs());
  }

  void _scheduleMuteExpiry() {
    _muteExpiryTimer?.cancel();
    _muteExpiryTimer = null;
    final now = DateTime.now().millisecondsSinceEpoch;
    int? nearest;
    for (final until in _mutedUntil.values) {
      if (until <= 0) continue;
      if (until <= now) {
        nearest = now;
        break;
      }
      if (nearest == null || until < nearest) nearest = until;
    }
    if (nearest == null) {
      if (_mutedUntil.values.any((v) => v > 0 && v <= now)) {
        _applyLocalDialogPrefs(_dialogs);
        notifyListeners();
      }
      return;
    }
    final wait = Duration(milliseconds: (nearest - now).clamp(0, 24 * 3600 * 1000));
    _muteExpiryTimer = Timer(wait, () {
      _applyLocalDialogPrefs(_dialogs);
      notifyListeners();
      _scheduleMuteExpiry();
    });
  }

  String? _prefsKeyFor(String? dlgId) {
    final trimmed = dlgId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    for (final key in _mutedUntil.keys) {
      if (_sameDlgId(key, trimmed)) return key;
    }
    for (final key in _archivedIds) {
      if (_sameDlgId(key, trimmed)) return key;
    }
    return trimmed;
  }

  bool _hasPrefId(Set<String> ids, String? dlgId) {
    final trimmed = dlgId?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    if (ids.contains(trimmed)) return true;
    return ids.any((id) => _sameDlgId(id, trimmed));
  }

  int? _prefValue(Map<String, int> map, String? dlgId) {
    final trimmed = dlgId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final direct = map[trimmed];
    if (direct != null) return direct;
    for (final e in map.entries) {
      if (_sameDlgId(e.key, trimmed)) return e.value;
    }
    return null;
  }

  void _removePrefKey(Map<String, int> map, String? dlgId) {
    final trimmed = dlgId?.trim() ?? '';
    if (trimmed.isEmpty) return;
    map.removeWhere((key, _) => _sameDlgId(key, trimmed));
  }

  void _removePrefId(Set<String> ids, String? dlgId) {
    final trimmed = dlgId?.trim() ?? '';
    if (trimmed.isEmpty) return;
    ids.removeWhere((id) => _sameDlgId(id, trimmed));
  }

  static bool _sameDlgId(String? a, String? b) {
    if (a == null || b == null) return false;
    final sa = a.trim();
    final sb = b.trim();
    if (sa.isEmpty || sb.isEmpty) return false;
    if (sa == sb) return true;
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    return na != null && nb != null && na == nb;
  }

  void _bumpDialog(String dlgId) {
    final idx = _dialogs.indexWhere((d) => _sameDlgId(d.id, dlgId));
    if (idx < 0) return;
    final dialog = _dialogs.removeAt(idx);
    var insertAt = 0;
    if (!dialog.isPinned) {
      insertAt = _dialogs.indexWhere((d) => !d.isPinned);
      if (insertAt < 0) insertAt = _dialogs.length;
    }
    _dialogs.insert(insertAt, dialog);
  }

  void _updateDialogPreview(DialogsListViewModel dialog, MessageViewModel m) {
    dialog.last_msg = _previewFor(m);
    dialog.last_msg_dttmcr = m.dtshow.isNotEmpty ? m.dtshow : _nowTime();
    dialog.last_msg_fr_name = m.my ? 'Вы' : m.fr_name;
    dialog.last_msg_status = m.my ? m.status : -2;
    if (MsgListCursors.isSavedMessage(m)) {
      dialog.last_msg_id = m.id;
    }
    dialog.last_msg_fr_id = m.my
        ? (_profile?.id ?? '')
        : (m.fr_id ?? dialog.last_msg_fr_id);
  }

  void _appendOutgoingSkeleton(
    DialogsListViewModel dialog,
    MessageViewModel skeleton, {
    required String preview,
  }) {
    dialog.messages.add(skeleton);
    MessageMapper.applyGrouping(
      dialog.messages,
      isGroupChat: dialog.isGrp,
    );
    _updateDialogPreview(dialog, skeleton);
    if (dialog.id != null) _bumpDialog(dialog.id!);
    notifyListeners();
  }

  Future<void> sendMessage(String text, {String prnId = ''}) async {
    final dialog = selectedDialog;
    final dlgId = dialog?.id;
    final trimmed = EmoticonReplacer.replace(text.trim());
    if (dialog == null || dlgId == null || trimmed.isEmpty) return;
    if (dialog.isNewContactWithoutDialog &&
        (dialog.usr_id?.trim().isEmpty ?? true)) {
      return;
    }

    final connected =
        _connectionStatus == ConnectionStatus.connected && _api.isConnected;

    final hash = ClientMsgHash.generate();
    final nowIso = _nowIso();
    final last = dialog.messages.isNotEmpty ? dialog.messages.last : null;
    final sameAuthorAsPrev = last?.my == true;
    final replyTo = _replyToMessage;
    final effectivePrnId = prnId.trim().isNotEmpty
        ? prnId.trim()
        : (replyTo?.referenceId ?? '');

    final skeleton = MessageViewModel(
      id: hash,
      type: 'text',
      my: true,
      body: trimmed,
      text: trimmed,
      fr_name: _profile?.name ?? 'Вы',
      fr_id: _profile?.id,
      dttmcr: nowIso,
      dtshow: _nowTime(),
      status: -1,
      hash: hash,
      prn_id: effectivePrnId,
      prn_fr_name: replyTo != null && effectivePrnId.isNotEmpty
          ? replyTo.quotedAuthorName
          : '',
      prn_body: replyTo != null && effectivePrnId.isNotEmpty
          ? replyTo.wirePrnBody
          : '',
      prn_fr_id: replyTo?.fr_id ?? '',
      prn_type: replyTo != null && effectivePrnId.isNotEmpty
          ? (replyTo.isCall ? 'call' : replyTo.type)
          : '',
      prn_fileTitle: replyTo?.fileTitle ?? '',
      prn_firstFile: replyTo?.quotedFirstFile,
      showUserName: false,
      avaOnTop: !sameAuthorAsPrev,
      avaOnBottom: true,
    );

    _replyToMessage = null;

    _appendOutgoingSkeleton(dialog, skeleton, preview: trimmed);

    if (!connected) return;

    try {
      final payload = <String, dynamic>{
        'type': 'txt',
        'hash': hash,
        'ai': 0,
        'body': trimmed,
      };
      _applyMsgTarget(payload, dialog);
      if (effectivePrnId.isNotEmpty) {
        payload['prn_id'] = effectivePrnId;
      }
      _api.sendMsg(payload);
    } catch (e) {
      ApiLogger.instance.logEvent('SEND', 'txt: $e');
      notifyListeners();
    }
  }

  Future<void> sendMediaMessage(List<MediaFile> files, {String caption = ''}) async {
    final dialog = selectedDialog;
    final dlgId = dialog?.id;
    final batch = files.take(10).toList();
    if (dialog == null || dlgId == null || batch.isEmpty) return;

    final connected =
        _connectionStatus == ConnectionStatus.connected && _api.isConnected;

    final cap = EmoticonReplacer.replace(caption.trim());
    final hash = ClientMsgHash.generate();
    final nowIso = _nowIso();
    final last = dialog.messages.isNotEmpty ? dialog.messages.last : null;
    final sameAuthorAsPrev = last?.my == true;
    final preview = cap.isNotEmpty
        ? cap
        : (batch.length > 1 ? 'Фотографии (${batch.length})' : 'Фотография');

    final skeleton = MessageViewModel(
      id: hash,
      type: 'media',
      my: true,
      body: cap,
      text: cap,
      fr_name: _profile?.name ?? 'Вы',
      fr_id: _profile?.id,
      dttmcr: nowIso,
      dtshow: _nowTime(),
      status: -1,
      hash: hash,
      showUserName: false,
      avaOnTop: !sameAuthorAsPrev,
      avaOnBottom: true,
      files: batch,
      size: const MsgSize(248, 248),
    );

    _appendOutgoingSkeleton(dialog, skeleton, preview: preview);

    if (!connected) return;

    try {
      // Кадр UI со скелетоном до ресайза/upload.
      await Future<void>.delayed(Duration.zero);

      final uploadedEntries = <Map<String, String>>[];
      final updatedFiles = <MediaFile>[];

      for (final file in batch) {
        final prepared = await MediaPreprocessor.prepare(
          originalName: file.fname.isNotEmpty ? file.fname : 'screenshot.png',
          bytes: file.bytes,
          path: file.URL,
        );

        // Сразу показать лёгкий JPEG в пузыре (вместо исходного Retina PNG).
        final previewFile = MediaFile(
          fname: prepared.fileName,
          kind: 'jpeg',
          size: prepared.bytes.length,
          width: prepared.width,
          height: prepared.height,
          bytes: prepared.bytes,
          URL: file.URL,
        );
        skeleton.files = [
          ...updatedFiles,
          previewFile,
          ...batch.skip(updatedFiles.length + 1),
        ];
        notifyListeners();

        final result = await _api.uploadMediaWithDimensions(
          bytes: prepared.bytes,
          originalName: prepared.fileName,
          duration: prepared.duration,
          width: prepared.width,
          height: prepared.height,
        );
        final uploaded = result.file;

        uploadedEntries.add(
          result.toMediaBodyEntry(duration: prepared.duration.toString()),
        );

        updatedFiles.add(MediaFile(
          hash: uploaded.hash,
          url: uploaded.publicUrl,
          fname: uploaded.fname,
          fdir: uploaded.fdir,
          kind: uploaded.kind,
          size: uploaded.size,
          width: result.width,
          height: result.height,
          duration: prepared.duration,
          uploaded: true,
          bytes: prepared.bytes,
          URL: file.URL,
        ));
        skeleton.files = [
          ...updatedFiles,
          ...batch.skip(updatedFiles.length),
        ];
        notifyListeners();
      }

      skeleton.files = updatedFiles;

      final bodyJson = jsonEncode({
        'desc': cap,
        'files': uploadedEntries,
      });

      final payload = <String, dynamic>{
        'type': 'media',
        'hash': hash,
        'ai': 0,
        'body': bodyJson,
      };
      _applyMsgTarget(payload, dialog);
      _api.sendMsg(payload);
    } catch (e) {
      ApiLogger.instance.logEvent('UPLOAD', 'media: $e');
      notifyListeners();
    }
  }

  Future<void> _loadEmojiCatalog() async {
    try {
      final categories = await _api.fetchEmojiList();
      final all = <String>[];
      for (final category in categories) {
        for (final item in category.emojis) {
          final emoji = item.emoji.trim();
          if (emoji.isNotEmpty && !all.contains(emoji)) {
            all.add(emoji);
          }
        }
      }
      if (all.isNotEmpty) {
        _quickReactions = TelegramReactions.mergeCatalog(all);
        notifyListeners();
      }
    } catch (_) {}
  }

  void addReaction(MessageViewModel message, String emoji) {
    unawaited(toggleReaction(message, emoji));
  }

  Future<void> toggleReaction(
    MessageViewModel message,
    String emoji, {
    bool remove = false,
  }) async {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;

    final dlgId = selectedDialog?.id?.trim();
    final usrId = _profile?.id.trim();
    if (dlgId == null || dlgId.isEmpty || usrId == null || usrId.isEmpty) {
      return;
    }

    final msgId = _serverMessageId(message);
    if (msgId == null) return;

    final result = _applyOptimisticLike(message, trimmed, remove: remove);
    notifyListeners();

    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    try {
      Map<String, dynamic>? resp;
      if (result.previousEmoji != null &&
          result.previousEmoji!.isNotEmpty &&
          !ReactionUtils.sameEmoji(result.previousEmoji!, trimmed)) {
        await _api.delLike(
          usrId: usrId,
          dlgId: dlgId,
          msgId: msgId,
          emoji: result.previousEmoji,
        );
      }
      if (result.removed) {
        resp = await _api.delLike(
          usrId: usrId,
          dlgId: dlgId,
          msgId: msgId,
          emoji: trimmed,
        );
      } else if (result.added) {
        resp = await _api.addLike(
          usrId: usrId,
          emoji: trimmed,
          dlgId: dlgId,
          msgId: msgId,
        );
      }
      if (resp != null) {
        _applyLikeWsResponse(msgId, resp);
      }
    } catch (_) {
      // Оптимистичное состояние уже показано; push/ошибка не откатываем жёстко.
    }
  }

  void _applyLikeWsResponse(String msgId, Map<String, dynamic> map) {
    _applyLikesUpdate(msgId, map);
  }

  /// Ответ/push `add_like` / `del_like`: полный список likes или точечное снятие.
  void _applyLikesUpdate(String msgId, Map<String, dynamic> map) {
    if (map['success'] == false) return;

    final type = map['type']?.toString() ?? '';
    final likes = LikesMapper.parseAddLikeResponse(
      map,
      currentUserId: _profile?.id,
      currentUserName: _reactionAuthorName,
    );

    final data = map['data'];
    final dataMap = data is Map ? Map<String, dynamic>.from(data) : null;
    final resolvedMsgId = msgId.trim().isNotEmpty
        ? msgId.trim()
        : (dataMap?['msg_id'] ?? map['msg_id'])?.toString().trim() ?? '';
    if (resolvedMsgId.isEmpty) return;

    final hasLikesPayload = LikesMapper.responseHasLikesPayload(map);
    final isDelLike = type == 'del_like';

    // Пустой body у del_like — не ошибка, а «реакция снята».
    if (!hasLikesPayload && !isDelLike && likes.isEmpty) {
      return;
    }

    for (final dialog in _dialogs) {
      for (final message in dialog.messages) {
        if (message.id != resolvedMsgId && message.hash != resolvedMsgId) {
          continue;
        }

        if (hasLikesPayload || likes.isNotEmpty) {
          MessageMapper.updateLikes(message, likes);
        } else if (isDelLike) {
          final usrId = dataMap?['usr_id']?.toString() ?? '';
          final emoji = dataMap?['emoji']?.toString() ?? '';
          _removeLikeFromMessage(
            message,
            userId: usrId,
            emoji: emoji,
          );
        }

        message.emoji = LikesMapper.enrichCurrentUser(
          message.emoji,
          currentUserId: _profile?.id,
          currentUserName: _reactionAuthorName,
        );
        notifyListeners();
        return;
      }
    }
  }

  void _removeLikeFromMessage(
    MessageViewModel message, {
    required String userId,
    required String emoji,
  }) {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    final targetEmoji = emoji.trim();
    final me = _reactionAuthorId;
    final working = [
      for (final r in message.emoji)
        MessageEmojiModel(
          emoji: r.emoji,
          my: r.my,
          qty: r.qty,
          usrName: List<String>.from(r.usrName),
          usrIds: List<String>.from(r.usrIds),
          avaColor: List<int>.from(r.avaColor),
          avatars: List<String>.from(r.avatars),
          date: List<String>.from(r.date),
        ),
    ];

    for (final reaction in working) {
      if (targetEmoji.isNotEmpty &&
          !ReactionUtils.sameEmoji(reaction.emoji, targetEmoji)) {
        continue;
      }
      final before = reaction.usrIds.length;
      _removeUserFromReaction(
        reaction,
        userId: uid,
        name: '',
      );
      // Сервер прислал наш usr_id, а в модели только my=true без id.
      if (reaction.usrIds.length == before &&
          reaction.my &&
          me.isNotEmpty &&
          ReactionUtils.sameUserId(uid, me)) {
        _removeUserFromReaction(
          reaction,
          userId: me,
          name: _reactionAuthorName,
        );
      }
    }

    message.emoji = LikesMapper.normalizeOnePerUser(
      working,
      currentUserId: _profile?.id,
    );
    _pruneEmptyReactions(message);
  }

  /// Список кто прочитал сообщение (`msg_read_list`).
  Future<List<MsgReadEntry>> fetchMsgReadList({
    required String dlgId,
    required String msgId,
  }) {
    return _api.fetchMsgReadList(dlgId: dlgId, msgId: msgId);
  }

  /// Метаданные диалога / участники (`dlg_info`) для экрана профиля собеседника.
  Future<DlgInfoResult> fetchDlgInfo(String dlgId) {
    return _api.fetchDlgInfo(
      dlgId: dlgId,
      currentUserId: _profile?.id,
    );
  }

  String? serverMessageId(MessageViewModel message) =>
      _serverMessageId(message);

  String? _serverMessageId(MessageViewModel message) {
    if (!MsgListCursors.isSavedMessage(message)) return null;
    final id = message.id.trim();
    return id.isEmpty ? null : id;
  }

  String get _reactionAuthorName {
    final name = _profile?.name.trim();
    return name != null && name.isNotEmpty ? name : 'Вы';
  }

  String get _reactionAuthorId => _profile?.id.trim() ?? '';

  bool _reactionHasUser(MessageEmojiModel reaction, String userId) {
    if (userId.isEmpty) return false;
    if (reaction.usrIds.any((id) => ReactionUtils.sameUserId(id, userId))) {
      return true;
    }
    return reaction.my && reaction.usrIds.isEmpty;
  }

  /// Оптимистичное обновление: одна реакция на пользователя, без промежуточных кадров.
  _ReactionApplyResult _applyOptimisticLike(
    MessageViewModel message,
    String emoji, {
    bool remove = false,
  }) {
    final name = _reactionAuthorName;
    final userId = _reactionAuthorId;
    if (userId.isEmpty) {
      return const _ReactionApplyResult();
    }

    // Копия списка — UI увидит только финальное состояние после notifyListeners.
    final working = LikesMapper.normalizeOnePerUser(
      [
        for (final r in message.emoji)
          MessageEmojiModel(
            emoji: r.emoji,
            my: r.my,
            qty: r.qty,
            usrName: List<String>.from(r.usrName),
            usrIds: List<String>.from(r.usrIds),
            avaColor: List<int>.from(r.avaColor),
            avatars: List<String>.from(r.avatars),
            date: List<String>.from(r.date),
          ),
      ],
      currentUserId: userId,
    );

    String? prev;
    for (final reaction in working) {
      if (_reactionHasUser(reaction, userId)) {
        prev = reaction.emoji;
        break;
      }
    }

    final sameAsCurrent =
        prev != null && ReactionUtils.sameEmoji(prev, emoji);
    final shouldRemove = remove || sameAsCurrent;

    for (final reaction in working) {
      _removeUserFromReaction(reaction, userId: userId, name: name);
    }

    var added = false;
    if (!shouldRemove) {
      MessageEmojiModel? target;
      for (final reaction in working) {
        if (ReactionUtils.sameEmoji(reaction.emoji, emoji)) {
          target = reaction;
          break;
        }
      }
      if (target != null) {
        target.my = true;
        target.usrIds = [...target.usrIds, userId];
        target.usrName = [...target.usrName, name];
        target.qty = target.usrIds.length;
      } else {
        working.add(
          MessageEmojiModel(
            emoji: emoji,
            my: true,
            qty: 1,
            usrName: [name],
            usrIds: [userId],
          ),
        );
      }
      added = true;
    }

    message.emoji = LikesMapper.normalizeOnePerUser(
      working,
      currentUserId: userId,
    );
    _pruneEmptyReactions(message);

    return _ReactionApplyResult(
      removed: shouldRemove && prev != null,
      added: added,
      previousEmoji:
          (!shouldRemove && prev != null && !sameAsCurrent) ? prev : null,
    );
  }

  void _removeUserFromReaction(
    MessageEmojiModel reaction, {
    required String userId,
    required String name,
  }) {
    var idx = reaction.usrIds.indexWhere(
      (id) => ReactionUtils.sameUserId(id, userId),
    );
    if (idx < 0 && name.trim().isNotEmpty) {
      idx = reaction.usrName.indexWhere((n) => n.trim() == name.trim());
    }
    if (idx < 0 &&
        reaction.my &&
        reaction.usrName.length == 1 &&
        ReactionUtils.sameUserId(userId, _reactionAuthorId)) {
      idx = 0;
    }
    if (idx >= 0) {
      if (idx < reaction.usrIds.length) {
        reaction.usrIds = [...reaction.usrIds]..removeAt(idx);
      }
      if (idx < reaction.usrName.length) {
        reaction.usrName = [...reaction.usrName]..removeAt(idx);
      }
      if (idx < reaction.avatars.length) {
        reaction.avatars = [...reaction.avatars]..removeAt(idx);
      }
      if (idx < reaction.avaColor.length) {
        reaction.avaColor = [...reaction.avaColor]..removeAt(idx);
      }
      if (idx < reaction.date.length) {
        reaction.date = [...reaction.date]..removeAt(idx);
      }
    }

    final me = _reactionAuthorId;
    reaction.my = me.isNotEmpty &&
        reaction.usrIds.any((id) => ReactionUtils.sameUserId(id, me));
    reaction.qty = reaction.usrName.length;
  }

  void _pruneEmptyReactions(MessageViewModel message) {
    message.emoji.removeWhere((r) => r.qty <= 0 || r.usrName.isEmpty);
  }

  /// Пересылка сообщения в один или несколько диалогов (WS `msg` + `repost: 1`).
  /// [comment] — необязательный текст, отправляемый отдельным сообщением.
  Future<void> forwardMessage(
    MessageViewModel source,
    List<String> targetDlgIds, {
    String comment = '',
  }) async {
    if (!ForwardMapper.canForward(source)) return;
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    final prnId = source.referenceId;
    if (prnId.isEmpty) return;

    final ids = targetDlgIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final trimmedComment = EmoticonReplacer.replace(comment.trim());

    for (final dlgId in ids) {
      final dialog = _dialogs.where((d) => _sameDlgId(d.id, dlgId)).firstOrNull;
      if (dialog == null) continue;

      final hash = ForwardMapper.newHash();
      final nowIso = _nowIso();
      final last = dialog.messages.isNotEmpty ? dialog.messages.last : null;
      final sameAuthorAsPrev = last?.my == true;

      final skeleton = ForwardMapper.buildSkeleton(
        source: source,
        hash: hash,
        prnId: prnId,
        profileName: _profile?.name ?? 'Вы',
        profileId: _profile?.id,
        nowIso: nowIso,
        nowTime: _nowTime(),
        sameAuthorAsPrev: sameAuthorAsPrev,
      );

      _appendOutgoingSkeleton(
        dialog,
        skeleton,
        preview: _previewFor(skeleton),
      );

      try {
        _api.sendMsg(
          ForwardMapper.buildPayload(
            source: source,
            dlgId: dlgId,
            hash: hash,
            prnId: prnId,
          ),
        );
      } catch (_) {
        skeleton.status = 0;
        notifyListeners();
      }

      if (trimmedComment.isNotEmpty) {
        _sendTextToDialog(dialog, trimmedComment);
      }
    }
  }

  /// Отправить обычное текстовое сообщение в произвольный диалог.
  void _sendTextToDialog(DialogsListViewModel dialog, String text) {
    final dlgId = dialog.id;
    if (dlgId == null || text.trim().isEmpty) return;
    if (dialog.isNewContactWithoutDialog) return;

    final hash = ClientMsgHash.generate();
    final nowIso = _nowIso();
    final last = dialog.messages.isNotEmpty ? dialog.messages.last : null;
    final sameAuthorAsPrev = last?.my == true;

    final skeleton = MessageViewModel(
      id: hash,
      type: 'text',
      my: true,
      body: text,
      text: text,
      fr_name: _profile?.name ?? 'Вы',
      fr_id: _profile?.id,
      dttmcr: nowIso,
      dtshow: _nowTime(),
      status: -1,
      hash: hash,
      showUserName: false,
      avaOnTop: !sameAuthorAsPrev,
      avaOnBottom: true,
    );

    _appendOutgoingSkeleton(dialog, skeleton, preview: text);

    try {
      final payload = <String, dynamic>{
        'type': 'txt',
        'hash': hash,
        'ai': 0,
        'body': text,
      };
      _applyMsgTarget(payload, dialog);
      _api.sendMsg(payload);
    } catch (_) {
      skeleton.status = 0;
      notifyListeners();
    }
  }

  void _onAddLikePush(Map<String, dynamic> map) {
    final data = map['data'];
    final msgId = (data is Map ? data['msg_id'] : map['msg_id'])?.toString();
    if (msgId == null || msgId.trim().isEmpty) return;
    _applyLikesUpdate(msgId, map);
  }

  /// Удаление сообщения: локально всегда; WS `msg_del` — если [forEveryone].
  void deleteMessage(String id, {required bool forEveryone}) {
    final dialog = selectedDialog;
    final dlgId = dialog?.id;
    if (dialog == null || dlgId == null) return;

    final target = dialog.messages.cast<MessageViewModel?>().firstWhere(
          (m) => m!.id == id || m.hash == id,
          orElse: () => null,
        );
    final deleteId = target?.id.trim().isNotEmpty == true
        ? target!.id
        : (target?.hash.trim().isNotEmpty == true ? target!.hash : id);

    if (!_removeMessagesFromDialog(dialog, [deleteId])) return;

    if (forEveryone) {
      final usrId = (_profile?.id ?? '').trim();
      if (usrId.isNotEmpty &&
          _connectionStatus == ConnectionStatus.connected &&
          _api.isConnected) {
        _api.sendMsgDel(
          usrId: usrId,
          dlgId: dlgId,
          ids: deleteId,
        );
      }
    }

    notifyListeners();
  }

  String _previewFor(MessageViewModel m) {
    if (m.isCall) {
      return m.callDisplay(currentUserId: _profile?.id)?.previewText ??
          (m.desc.trim().isNotEmpty
              ? m.desc.trim()
              : (m.text.trim().isNotEmpty ? m.text.trim() : 'Вызов'));
    }
    if (m.type == 'file') {
      final title = (m.fileTitle ?? '').trim();
      return title.isNotEmpty ? 'Файл: $title' : 'Файл';
    }
    if (m.isImage) {
      return m.files.length > 1 ? 'Медиафайлы' : 'Фотография';
    }
    if (m.isVoice) return 'Голосовое сообщение';
    if (m.isLocation) {
      if (m.locationLive) return 'Трансляция геопозиции';
      final adrs = (m.address ?? '').trim();
      if (adrs == 'Трансляция геопозиции завершена') return adrs;
      if (adrs.isEmpty || adrs == 'Геопозиция') return 'Геопозиция';
      if (adrs == 'Трансляция геопозиции') return adrs;
      return 'Геопозиция: $adrs';
    }
    final text = m.desc.trim().isNotEmpty
        ? m.desc.trim()
        : (m.body.isNotEmpty ? m.body.trim() : m.text.trim());
    // Не показываем сырой JSON обмена в списке чатов.
    if (text.startsWith('{') &&
        (text.contains('"desc"') || text.contains('"files"'))) {
      return DialogMapper.previewFromLastMsg(
        text,
        currentUserId: _profile?.id,
      );
    }
    return text;
  }

  /// Отправка файлов, перетащенных в чат из Finder/Explorer.
  /// [dlgId] — целевой диалог (drop на строку в списке); иначе текущий.
  Future<void> sendDroppedAttachments(
    List<MediaFile> files, {
    String? dlgId,
  }) async {
    if (files.isEmpty) return;
    final targetId = (dlgId ?? _selectedId)?.trim();
    if (targetId == null || targetId.isEmpty) return;

    if (_selectedId != targetId) {
      await selectDialog(targetId);
    }
    if (selectedDialog == null || selectedDialog!.id != targetId) return;

    final batch = files.take(10).toList();
    final media = <MediaFile>[];
    final docs = <MediaFile>[];
    for (final f in batch) {
      if (ChatFileDnd.isMediaAttachment(f)) {
        media.add(f);
      } else {
        docs.add(f);
      }
    }
    if (media.isNotEmpty) {
      await sendMediaMessage(media);
    }
    if (docs.isNotEmpty) {
      await sendFileMessage(docs);
    }
  }

  Future<void> sendFileMessage(List<MediaFile> files) async {
    final dialog = selectedDialog;
    final dlgId = dialog?.id;
    final batch = files.take(10).toList();
    if (dialog == null || dlgId == null || batch.isEmpty) return;

    final connected =
        _connectionStatus == ConnectionStatus.connected && _api.isConnected;

    final hash = ClientMsgHash.generate();
    final nowIso = _nowIso();
    final last = dialog.messages.isNotEmpty ? dialog.messages.last : null;
    final sameAuthorAsPrev = last?.my == true;
    final firstTitle = MediaDisplayName.forFile(batch.first, dttmcr: nowIso);
    final preview = batch.length > 1
        ? 'Файлы (${batch.length})'
        : firstTitle;

    final skeleton = MessageViewModel(
      id: hash,
      type: 'file',
      my: true,
      body: '',
      text: '',
      fr_name: _profile?.name ?? 'Вы',
      fr_id: _profile?.id,
      dttmcr: nowIso,
      dtshow: _nowTime(),
      status: -1,
      hash: hash,
      showUserName: false,
      avaOnTop: !sameAuthorAsPrev,
      avaOnBottom: true,
      files: batch,
      fileTitle: firstTitle,
      fileSize: batch.first.humanSize,
      fileFormat: batch.first.formatLabel,
    );

    _appendOutgoingSkeleton(dialog, skeleton, preview: preview);

    if (!connected) return;

    try {
      final uploadedEntries = <Map<String, String>>[];
      final updatedFiles = <MediaFile>[];

      for (final file in batch) {
        final title = MediaDisplayName.forFile(file, dttmcr: nowIso);
        final bytes = await _readAttachmentBytes(file);
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Не удалось прочитать файл $title');
        }

        final uploaded = await _api.uploadDocumentAttachment(
          bytes: bytes,
          originalName: title,
        );

        uploadedEntries.add(uploaded.toDocumentFileJson(title: title));
        updatedFiles.add(MediaFile(
          hash: uploaded.hash,
          url: uploaded.publicUrl,
          fname: uploaded.fname,
          fdir: uploaded.fdir,
          kind: uploaded.kind,
          size: uploaded.size,
          title: title,
          uploaded: true,
          bytes: file.bytes ?? bytes,
          URL: file.URL,
        ));
      }

      skeleton.files = updatedFiles;
      skeleton.fileTitle = firstTitle;

      final bodyJson = jsonEncode({
        'desc': '',
        'files': uploadedEntries,
      });

      final payload = <String, dynamic>{
        'type': 'file',
        'hash': hash,
        'ai': 0,
        'body': bodyJson,
      };
      _applyMsgTarget(payload, dialog);
      _api.sendMsg(payload);
    } catch (e) {
      ApiLogger.instance.logEvent('UPLOAD', 'file: $e');
      notifyListeners();
    }
  }

  /// Повторная отправка локальных скелетов после восстановления связи.
  Future<void> _resendPendingMessages() async {
    if (_connectionStatus != ConnectionStatus.connected || !_api.isConnected) {
      return;
    }

    var changed = false;
    for (final dialog in _dialogs) {
      final dlgId = dialog.id?.trim();
      if (dlgId == null || dlgId.isEmpty) continue;

      for (final message in dialog.messages) {
        if (!OutgoingMessagePayload.isPending(message)) continue;
        changed = true;
        await _resendOutgoingMessage(dialog, dlgId, message);
      }
    }

    if (changed) notifyListeners();
  }

  Future<void> _resendOutgoingMessage(
    DialogsListViewModel dialog,
    String dlgId,
    MessageViewModel message,
  ) async {
    try {
      if (OutgoingMessagePayload.needsUpload(message)) {
        final type = message.type.toLowerCase();
        if (type == 'file' || message.isFile) {
          await _resendFileUpload(dialog, message);
        } else {
          await _resendMediaUpload(dialog, message);
        }
        return;
      }

      final payload = OutgoingMessagePayload.buildForDialog(
        message: message,
        dialog: dialog,
      );
      if (payload == null) return;

      _api.sendMsg(payload);
    } catch (e) {
      ApiLogger.instance.logEvent('RESEND', '$dlgId ${message.hash}: $e');
    }
  }

  Future<void> _resendMediaUpload(
    DialogsListViewModel dialog,
    MessageViewModel message,
  ) async {
    if (message.files.isEmpty) return;

    final uploadedEntries = <Map<String, String>>[];
    final updatedFiles = <MediaFile>[];

    for (final file in message.files) {
      if (file.hash.trim().isNotEmpty &&
          file.fdir.trim().isNotEmpty &&
          file.fname.trim().isNotEmpty) {
        uploadedEntries.add(
          UploadedFileInfo(
            hash: file.hash,
            fname: file.fname,
            fdir: file.fdir,
            kind: file.kind,
            size: file.size,
          ).toMediaFileJson(
            width: file.width,
            height: file.height,
            duration: file.duration.toString(),
            preview: file.preview,
          ),
        );
        updatedFiles.add(file);
        continue;
      }

      final prepared = await MediaPreprocessor.prepare(
        originalName: file.fname,
        bytes: file.bytes,
        path: file.URL,
      );
      final result = await _api.uploadMediaWithDimensions(
        bytes: prepared.bytes,
        originalName: prepared.fileName,
        duration: prepared.duration,
        width: prepared.width,
        height: prepared.height,
      );
      final uploaded = result.file;
      uploadedEntries.add(
        result.toMediaBodyEntry(duration: prepared.duration.toString()),
      );
      updatedFiles.add(MediaFile(
        hash: uploaded.hash,
        url: uploaded.publicUrl,
        fname: uploaded.fname,
        fdir: uploaded.fdir,
        kind: uploaded.kind,
        size: uploaded.size,
        width: result.width,
        height: result.height,
        duration: prepared.duration,
        uploaded: true,
        bytes: prepared.bytes,
        URL: file.URL,
      ));
    }

    message.files = updatedFiles;
    final payload = <String, dynamic>{
      'type': 'media',
      'hash': message.hash.trim().isNotEmpty ? message.hash : message.id,
      'ai': message.ai,
      'body': jsonEncode({
        'desc': message.desc.trim().isNotEmpty
            ? message.desc.trim()
            : message.body.trim(),
        'files': uploadedEntries,
      }),
    };
    _applyMsgTarget(payload, dialog);
    _api.sendMsg(payload);
  }

  Future<void> _resendFileUpload(
    DialogsListViewModel dialog,
    MessageViewModel message,
  ) async {
    if (message.files.isEmpty) return;

    final uploadedEntries = <Map<String, String>>[];
    final updatedFiles = <MediaFile>[];

    for (final file in message.files) {
      if (file.hash.trim().isNotEmpty &&
          file.fdir.trim().isNotEmpty &&
          file.fname.trim().isNotEmpty) {
        final title = file.title.isNotEmpty ? file.title : file.fname;
        uploadedEntries.add(
          UploadedFileInfo(
            hash: file.hash,
            fname: file.fname,
            fdir: file.fdir,
            kind: file.kind,
            size: file.size,
          ).toDocumentFileJson(title: title),
        );
        updatedFiles.add(file);
        continue;
      }

      final title = MediaDisplayName.forFile(file, dttmcr: message.dttmcr);
      final bytes = await _readAttachmentBytes(file);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Не удалось прочитать файл $title');
      }
      final uploaded = await _api.uploadDocumentAttachment(
        bytes: bytes,
        originalName: title,
      );
      uploadedEntries.add(
        uploaded.toDocumentFileJson(title: title),
      );
      updatedFiles.add(MediaFile(
        hash: uploaded.hash,
        url: uploaded.publicUrl,
        fname: uploaded.fname,
        fdir: uploaded.fdir,
        kind: uploaded.kind,
        size: uploaded.size,
        title: title,
        uploaded: true,
        bytes: file.bytes ?? bytes,
        URL: file.URL,
      ));
    }

    message.files = updatedFiles;
    final payload = <String, dynamic>{
      'type': 'file',
      'hash': message.hash.trim().isNotEmpty ? message.hash : message.id,
      'ai': message.ai,
      'body': jsonEncode({
        'desc': message.desc.trim(),
        'files': uploadedEntries,
      }),
    };
    _applyMsgTarget(payload, dialog);
    _api.sendMsg(payload);
  }

  Future<Uint8List?> _readAttachmentBytes(MediaFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return file.bytes;
    }
    final path = file.URL;
    if (path != null && path.isNotEmpty) {
      try {
        return await File(path).readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  @override
  void dispose() {
    _stopDialogsLiveSync();
    FirebaseService.instance.onChatRelatedPush = null;
    _api.onMsgPush = null;
    _api.onMsgListPush = null;
    _api.onDlgCreatedPush = null;
    _api.onStatusPush = null;
    _api.onMsgDelPush = null;
    _api.onAddLikePush = null;
    _api.onForceLogOut = null;
    _api.onDisconnected = null;
    _api.dispose();
    super.dispose();
  }
}

class _PendingUnknownDialogPush {
  final Map<String, dynamic>? listData;
  final MessageViewModel? message;

  const _PendingUnknownDialogPush._({this.listData, this.message});

  factory _PendingUnknownDialogPush.single(
    Map<String, dynamic> _,
    MessageViewModel message,
  ) =>
      _PendingUnknownDialogPush._(message: message);

  factory _PendingUnknownDialogPush.list(Map<String, dynamic> data) =>
      _PendingUnknownDialogPush._(listData: Map<String, dynamic>.from(data));
}

class _ReactionApplyResult {
  final bool removed;
  final bool added;
  final String? previousEmoji;

  const _ReactionApplyResult({
    this.removed = false,
    this.added = false,
    this.previousEmoji,
  });
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
