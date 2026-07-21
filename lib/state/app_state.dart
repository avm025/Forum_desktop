import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../api/contacts_service.dart';
import '../api/device_id_service.dart';
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
import '../models/device_session.dart';
import '../models/dialog_group.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/forum_database.dart';
import '../models/telegram_reactions.dart';
import '../models/media_file.dart';
import '../models/message_emoji_model.dart';
import '../models/message_view_model.dart';
import '../models/user_profile.dart';
import '../services/appearance_prefs.dart';
import '../services/api_logger.dart';
import '../services/auth_session.dart';
import '../services/firebase_service.dart';
import '../services/forum_cache.dart';
import '../theme/app_theme.dart';
import '../theme/appearance_resolver.dart';
import '../utils/emoticon_replacer.dart';
import '../utils/folder_list_codec.dart';
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
  static const ai = '__ai__';
  static const personal = '__personal__';

  static const maxFolderNameLength = 24;

  static bool isBuiltin(String tabId) =>
      tabId == all || tabId == ai || tabId == personal;

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
    _api.onStatusPush = _onStatusPush;
    _api.onMsgDelPush = _onMsgDelPush;
    _api.onAddLikePush = _onAddLikePush;
    _api.onForceLogOut = _onForceLogOut;
    _api.onDisconnected = _scheduleReconnect;
    FirebaseService.instance.bindApiClient(_api);
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

  String? _selectedId;
  String _activeTab = BuiltinTab.all;
  String get activeTab => _activeTab;

  String _search = '';

  BottomNavTab _navTab = BottomNavTab.chats;
  BottomNavTab get navTab => _navTab;

  bool _messagesLoading = false;
  bool _messagesLoadingOlder = false;
  String? _messagesError;
  final Set<String> _messagesLoadedFor = {};
  final Map<String, bool> _msgHasMore = {};
  final Map<String, Future<void>> _messageLoadsInFlight = {};
  final Map<String, ChatScrollAnchor> _chatScrollAnchors = {};
  final Map<String, void Function()> _chatScrollSavers = {};
  int _loadGeneration = 0;
  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  bool _profileAvatarUploading = false;
  bool get profileAvatarUploading => _profileAvatarUploading;

  String get search => _search;
  bool get isLoading => _connectionStatus == ConnectionStatus.connecting;
  bool get messagesLoading => _messagesLoading;
  bool get messagesLoadingOlder => _messagesLoadingOlder;
  String? get messagesError => _messagesError;

  MessageViewModel? _replyToMessage;
  MessageViewModel? get replyToMessage => _replyToMessage;

  List<String> _quickReactions = List.of(kTelegramReactionEmojis);
  List<String> get quickReactions => List.unmodifiable(_quickReactions);

  void setReplyTo(MessageViewModel message) {
    _replyToMessage = message;
    notifyListeners();
  }

  void clearReplyTo() {
    if (_replyToMessage == null) return;
    _replyToMessage = null;
    notifyListeners();
  }

  bool hasMoreMessages(String? dlgId) =>
      dlgId != null && (_msgHasMore[dlgId] ?? false);

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
      await ForumCache.instance.clearAll();
      _profile = null;
      _dialogs = [];
      _groups = [];
      _selectedId = null;
      _messagesLoadedFor.clear();
      _msgHasMore.clear();
      _messageLoadsInFlight.clear();
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

      final dialogsFuture = _api.fetchDialogs(contacts);
      final groupsFuture = _api.fetchGroups();

      _dialogs = _mergePreservingMessages(await dialogsFuture);
      _connectionStatus = ConnectionStatus.connected;
      _connectionError = null;
      _ensureDefaultSelection();
      notifyListeners();

      try {
        _groups = await groupsFuture;
      } on ForumApiException {
        // Папки не критичны.
      }

      unawaited(_loadEmojiCatalog());
      unawaited(_resendPendingMessages());

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
      _dialogs = _api.parseDialogsResponse(dialogsMap);
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
      if (id != null && id.isNotEmpty && dialog.messages.isNotEmpty) {
        await preloadChatScrollAnchor(id);
      }
    }

    return restored;
  }

  Future<void> _restoreMessagesFromCache(String dlgId) async {
    final map = await ForumCache.instance.loadMessages(dlgId);
    if (map == null || map['success'] != true) return;

    final dialog = _dialogs.where((d) => d.id == dlgId).firstOrNull;
    if (dialog == null) return;

    try {
      final result = _api.parseMsgListResponse(
        map,
        expectedDlgId: dlgId,
        currentUserId: _profile?.id,
        isGroupChat: dialog.isGrp,
      );
      if (result.messages.isEmpty) return;
      dialog.messages = result.messages;
      _msgHasMore[dlgId] = result.hasMoreHistory;
    } catch (_) {}
  }

  void _ensureDefaultSelection() {
    if (_selectedId == null && _dialogs.isNotEmpty) {
      _selectedId = _dialogs.first.id;
    } else if (_selectedId != null &&
        !_dialogs.any((d) => d.id == _selectedId)) {
      _selectedId = _dialogs.isNotEmpty ? _dialogs.first.id : null;
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
    notifyListeners();
  }

  void setSearch(String value) {
    _search = value;
    notifyListeners();
  }

  /// Вкладки: Все, ИИ, Личное + папки с сервера.
  List<({String id, String label})> get tabs {
    final items = <({String id, String label})>[
      (id: BuiltinTab.all, label: 'Все'),
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
    if (created != null) {
      _activeTab = created.id;
      notifyListeners();
    }
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

  List<DialogsListViewModel> get dialogs {
    Iterable<DialogsListViewModel> list = _dialogs;

    if (_activeTab == BuiltinTab.ai) {
      list = list.where((d) => (d.ai ?? 0) > 0);
    } else if (_activeTab == BuiltinTab.personal) {
      list = list.where((d) => !d.isGrp);
    } else if (_activeTab != BuiltinTab.all) {
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

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((d) =>
          d.chatName.toLowerCase().contains(q) ||
          d.last_msg.toLowerCase().contains(q));
    }

    return list.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return 0;
      });
  }

  String? get selectedId => _selectedId;

  DialogsListViewModel? get selectedDialog {
    if (_selectedId == null) return null;
    for (final d in _dialogs) {
      if (d.id == _selectedId) return d;
    }
    return null;
  }

  Future<void> selectDialog(String? id) async {
    if (_selectedId == id) return;
    _flushChatScroll(_selectedId);
    _replyToMessage = null;
    final previousId = _selectedId;
    _selectedId = id;
    _messagesError = null;
    final d = selectedDialog;
    if (d != null && d.unread > 0) d.unread = 0;

    if (id == null) {
      notifyListeners();
      return;
    }

    await preloadChatScrollAnchor(id);
    notifyListeners();

    if (_connectionStatus == ConnectionStatus.connected) {
      loadMessages(id);
    } else {
      await _restoreMessagesFromCache(id);
      if (_selectedId == id) notifyListeners();
    }

    // Повторный flush предыдущего чата после notify — на случай позднего commit.
    if (previousId != null && !dlgIdsEqual(previousId, id)) {
      _flushChatScroll(previousId);
    }
  }

  /// Загрузить первую страницу истории (msg_list).
  Future<void> loadMessages(String dlgId, {bool force = false}) {
    if (!force && _messagesLoadedFor.contains(dlgId)) {
      return Future.value();
    }

    final existing = _messageLoadsInFlight[dlgId];
    if (!force && existing != null) return existing;

    final future = _loadMessagesImpl(dlgId, force: force);
    _messageLoadsInFlight[dlgId] = future;
    return future.whenComplete(() => _messageLoadsInFlight.remove(dlgId));
  }

  Future<void> _loadMessagesImpl(String dlgId, {bool force = false}) async {
    final sessionCached = _messagesLoadedFor.contains(dlgId);
    if (!force && sessionCached) return;

    final gen = ++_loadGeneration;
    final dialog = _dialogs.where((d) => d.id == dlgId).firstOrNull;

    if (force) {
      _msgHasMore.remove(dlgId);
      _messagesLoadedFor.remove(dlgId);
    }

    if (!sessionCached) {
      await _restoreMessagesFromCache(dlgId);
    }

    final hasLocalMessages = dialog != null && dialog.messages.isNotEmpty;

    if (!sessionCached || force) {
      _messagesLoading = !hasLocalMessages;
      _messagesError = null;
      notifyListeners();
    }

    try {
      final request = _buildMsgListRequest(dialog);
      final result = await _api.fetchMessageList(
        dlgId,
        request: request,
        currentUserId: _profile?.id,
        isGroupChat: dialog?.isGrp ?? false,
      );

      if (gen != _loadGeneration || _selectedId != dlgId) return;

      if (dialog != null) {
        MsgListMerge.apply(
          dialog: dialog,
          result: result,
          onHistoryPagination: (hasMore) => _msgHasMore[dlgId] = hasMore,
        );
        _messagesLoadedFor.add(dlgId);
        _messagesError = null;
        if (!result.isHistory && _sameDlgId(_selectedId, dlgId)) {
          _sendReadStatus(dialog, dlgId);
        }
      }
    } on ForumApiException catch (e) {
      if (gen == _loadGeneration && _selectedId == dlgId) {
        if (!hasLocalMessages) _messagesError = e.message;
      }
    } catch (e) {
      if (gen == _loadGeneration && _selectedId == dlgId) {
        if (!hasLocalMessages) _messagesError = e.toString();
      }
    } finally {
      if (gen == _loadGeneration && _selectedId == dlgId) {
        _messagesLoading = false;
        notifyListeners();
      }
    }
  }

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

    final oldest = MsgListCursors.firstSaved(dialog.messages);
    if (oldest == null) {
      _msgHasMore[dlgId] = false;
      return;
    }

    _messagesLoadingOlder = true;
    notifyListeners();

    try {
      final result = await _api.fetchMessageList(
        dlgId,
        request: MsgListRequest.history(oldest.id),
        currentUserId: _profile?.id,
        isGroupChat: dialog.isGrp,
      );

      if (_selectedId != dlgId) return;

      if (result.messages.isEmpty) {
        _msgHasMore[dlgId] = false;
        return;
      }

      MsgListMerge.apply(
        dialog: dialog,
        result: result,
        onHistoryPagination: (hasMore) => _msgHasMore[dlgId] = hasMore,
      );
    } on ForumApiException catch (e) {
      if (_selectedId == dlgId) _messagesError = e.message;
    } catch (e) {
      if (_selectedId == dlgId) _messagesError = e.toString();
    } finally {
      _messagesLoadingOlder = false;
      notifyListeners();
    }
  }

  void clearSelection() {
    _flushChatScroll(_selectedId);
    _replyToMessage = null;
    _selectedId = null;
    notifyListeners();
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

    final msgDlgId = _extractDlgId(data);
    if (msgDlgId == null) return;

    final dialog = _findDialog(msgDlgId);
    if (dialog == null) {
      ApiLogger.instance.logEvent('MSG', 'диалог не найден: $msgDlgId');
      return;
    }

    final message = MessageMapper.fromServerJson(
      data,
      currentUserId: _profile?.id,
    );

    _applySingleMessage(dialog, msgDlgId, message);
  }

  void _onMsgListPush(Map<String, dynamic> data) {
    final msgDlgId = _extractDlgId(data);
    if (msgDlgId == null) return;

    final dialog = _findDialog(msgDlgId);
    if (dialog == null) {
      ApiLogger.instance.logEvent('MSG_LIST', 'диалог не найден: $msgDlgId');
      return;
    }

    final raw = data['msgs'];
    if (raw is! List || raw.isEmpty) return;

    try {
      final result = _api.parseMsgListResponse(
        {'success': true, 'data': data},
        expectedDlgId: msgDlgId,
        currentUserId: _profile?.id,
        isGroupChat: dialog.isGrp,
      );
      _mergeMsgListResult(dialog, msgDlgId, result);
    } catch (e) {
      ApiLogger.instance.logEvent('MSG_LIST', 'ошибка push: $e');
    }
  }

  String? _extractDlgId(Map<String, dynamic> data) {
    final id = data['dlg_id'] ?? data['dialog_id'] ?? data['dlgId'];
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
    if (isOpen) {
      _messagesLoadedFor.add(dlgId);
      if (!message.my) {
        _sendReadStatus(dialog, dlgId);
      }
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
    if (result.messages.isEmpty) return;

    final beforeCount = dialog.messages.length;

    MsgListMerge.apply(
      dialog: dialog,
      result: result,
      onHistoryPagination: (hasMore) {
        if (result.isHistory) _msgHasMore[dlgId] = hasMore;
      },
    );
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

    _updateDialogPreview(dialog, result.messages.last);
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
    }
    return incoming;
  }

  void _scheduleReconnect() {
    if (!_isAuthenticated) return;
    if (_reconnectPending) return;
    _reconnectPending = true;
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
        unawaited(_resendPendingMessages());
        final openId = _selectedId;
        if (openId != null) {
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
    if (idx > 0) {
      final dialog = _dialogs.removeAt(idx);
      _dialogs.insert(0, dialog);
    }
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
    final last = dialog.messages.isNotEmpty ? dialog.messages.last : null;
    if (last != null) last.avaOnBottom = false;

    dialog.messages.add(skeleton);
    _updateDialogPreview(dialog, skeleton);
    if (dialog.id != null) _bumpDialog(dialog.id!);
    notifyListeners();
  }

  Future<void> sendMessage(String text, {String prnId = ''}) async {
    final dialog = selectedDialog;
    final dlgId = dialog?.id;
    final trimmed = EmoticonReplacer.replace(text.trim());
    if (dialog == null || dlgId == null || trimmed.isEmpty) return;

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
          ? replyTo.quotedPreviewText
          : '',
      prn_fr_id: replyTo?.fr_id ?? '',
      prn_type: replyTo?.type ?? '',
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
        'dlg_id': dlgId,
        'ai': 0,
        'body': trimmed,
      };
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
      final uploadedEntries = <Map<String, String>>[];
      final updatedFiles = <MediaFile>[];

      for (final file in batch) {
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

      skeleton.files = updatedFiles;

      final bodyJson = jsonEncode({
        'desc': cap,
        'files': uploadedEntries,
      });

      _api.sendMsg({
        'type': 'media',
        'hash': hash,
        'dlg_id': dlgId,
        'ai': 0,
        'body': bodyJson,
      });
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
    toggleReaction(message, emoji);
  }

  void toggleReaction(
    MessageViewModel message,
    String emoji, {
    bool remove = false,
  }) {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;

    final dlgId = selectedDialog?.id?.trim();
    final usrId = _profile?.id.trim();
    if (dlgId == null || dlgId.isEmpty || usrId == null || usrId.isEmpty) {
      return;
    }

    final msgId = _serverMessageId(message);
    if (msgId == null) return;

    final removing = _applyOptimisticLike(message, trimmed, remove: remove);
    notifyListeners();

    if (_connectionStatus == ConnectionStatus.connected && _api.isConnected) {
      if (removing) {
        _api.sendDelLike(
          usrId: usrId,
          dlgId: dlgId,
          msgId: msgId,
          emoji: trimmed,
        );
      } else {
        _api.sendAddLike(
          usrId: usrId,
          emoji: trimmed,
          dlgId: dlgId,
          msgId: msgId,
        );
      }
    }
  }

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

  String? _findUserReactionEmoji(MessageViewModel message, String userId) {
    for (final reaction in message.emoji) {
      for (var i = 0; i < reaction.usrIds.length; i++) {
        if (ReactionUtils.sameUserId(reaction.usrIds[i], userId)) {
          return reaction.emoji;
        }
      }
      if (reaction.my && reaction.usrIds.isEmpty && reaction.usrName.isNotEmpty) {
        return reaction.emoji;
      }
    }
    return null;
  }

  bool _reactionHasUser(MessageEmojiModel reaction, String userId) {
    if (userId.isEmpty) return false;
    if (reaction.usrIds.any((id) => ReactionUtils.sameUserId(id, userId))) {
      return true;
    }
    return reaction.my && reaction.usrIds.isEmpty;
  }

  bool _applyOptimisticLike(
    MessageViewModel message,
    String emoji, {
    bool remove = false,
  }) {
    message.emoji = LikesMapper.normalizeOnePerUser(
      List<MessageEmojiModel>.from(message.emoji),
      currentUserId: _reactionAuthorId,
    );

    final name = _reactionAuthorName;
    final userId = _reactionAuthorId;
    if (userId.isEmpty) return false;

    final currentEmoji = _findUserReactionEmoji(message, userId);
    final shouldRemove = remove ||
        (currentEmoji != null &&
            ReactionUtils.sameEmoji(currentEmoji, emoji));

    if (shouldRemove) {
      for (final reaction in message.emoji) {
        _removeUserFromReaction(reaction, userId: userId, name: name);
      }
    } else {
      for (final reaction in message.emoji) {
        if (_reactionHasUser(reaction, userId)) {
          _removeUserFromReaction(reaction, userId: userId, name: name);
        }
      }

      MessageEmojiModel? target;
      for (final reaction in message.emoji) {
        if (ReactionUtils.sameEmoji(reaction.emoji, emoji)) {
          target = reaction;
          break;
        }
      }

      if (target != null &&
          !target.usrIds.any((id) => ReactionUtils.sameUserId(id, userId))) {
        target.my = true;
        target.usrIds = [...target.usrIds, userId];
        target.usrName = [...target.usrName, name];
        target.qty = target.usrIds.length;
      } else if (target == null) {
        message.emoji.add(
          MessageEmojiModel(
            emoji: emoji,
            my: true,
            qty: 1,
            usrName: [name],
            usrIds: [userId],
          ),
        );
      }
    }

    message.emoji = LikesMapper.normalizeOnePerUser(
      message.emoji,
      currentUserId: userId,
    );
    _pruneEmptyReactions(message);
    return shouldRemove;
  }

  void _removeUserFromReaction(
    MessageEmojiModel reaction, {
    required String userId,
    required String name,
  }) {
    var idx = reaction.usrIds.indexWhere(
      (id) => ReactionUtils.sameUserId(id, userId),
    );
    if (idx < 0) {
      idx = reaction.usrName.indexWhere((n) => n.trim() == name);
    }
    if (idx < 0 && reaction.my && reaction.usrName.length == 1) {
      idx = 0;
    }
    if (idx >= 0) {
      if (idx < reaction.usrIds.length) {
        reaction.usrIds = [...reaction.usrIds]..removeAt(idx);
      }
      reaction.usrName = [...reaction.usrName]..removeAt(idx);
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

    reaction.my =
        reaction.usrIds.any((id) => ReactionUtils.sameUserId(id, userId));
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
      _api.sendMsg({
        'type': 'txt',
        'hash': hash,
        'dlg_id': dlgId,
        'ai': 0,
        'body': text,
      });
    } catch (_) {
      skeleton.status = 0;
      notifyListeners();
    }
  }

  void _onAddLikePush(Map<String, dynamic> map) {
    if (map['success'] == false) return;

    final data = map['data'];
    final msgId = (data is Map ? data['msg_id'] : map['msg_id'])?.toString();
    if (msgId == null || msgId.trim().isEmpty) return;

    final likes = LikesMapper.parseAddLikeResponse(
      map,
      currentUserId: _profile?.id,
    );

    for (final dialog in _dialogs) {
      for (final message in dialog.messages) {
        if (message.id == msgId || message.hash == msgId) {
          MessageMapper.updateLikes(message, likes);
          notifyListeners();
          return;
        }
      }
    }
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
    if (m.type == 'file') return m.fileTitle ?? 'Файл';
    if (m.isImage) return 'Фотография';
    if (m.isVoice) return 'Голосовое сообщение';
    if (m.isLocation) return 'Геопозиция';
    return m.body.isNotEmpty ? m.body : m.text;
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
    final firstTitle =
        batch.first.fname.isNotEmpty ? batch.first.fname : 'Файл';
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
        final title = file.fname.isNotEmpty ? file.fname : 'Файл';
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

      _api.sendMsg({
        'type': 'file',
        'hash': hash,
        'dlg_id': dlgId,
        'ai': 0,
        'body': bodyJson,
      });
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
          await _resendFileUpload(dlgId, message);
        } else {
          await _resendMediaUpload(dlgId, message);
        }
        return;
      }

      final payload = OutgoingMessagePayload.build(
        message: message,
        dlgId: dlgId,
      );
      if (payload == null) return;

      _api.sendMsg(payload);
    } catch (e) {
      ApiLogger.instance.logEvent('RESEND', '$dlgId ${message.hash}: $e');
    }
  }

  Future<void> _resendMediaUpload(
    String dlgId,
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

    final cap = EmoticonReplacer.replace(
      (message.desc.trim().isNotEmpty
              ? message.desc
              : (message.body.trim().isNotEmpty ? message.body : message.text))
          .trim(),
    );

    _api.sendMsg({
      'type': 'media',
      'hash': message.hash,
      'dlg_id': dlgId,
      'ai': message.ai,
      'body': jsonEncode({
        'desc': cap,
        'files': uploadedEntries,
      }),
    });
  }

  Future<void> _resendFileUpload(
    String dlgId,
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
          ).toDocumentFileJson(
            title: file.title.isNotEmpty ? file.title : file.fname,
          ),
        );
        updatedFiles.add(file);
        continue;
      }

      final title = file.fname.isNotEmpty ? file.fname : 'Файл';
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

    message.files = updatedFiles;

    _api.sendMsg({
      'type': 'file',
      'hash': message.hash,
      'dlg_id': dlgId,
      'ai': message.ai,
      'body': jsonEncode({
        'desc': message.desc.trim(),
        'files': uploadedEntries,
      }),
    });
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
    _api.onMsgPush = null;
    _api.onMsgListPush = null;
    _api.onStatusPush = null;
    _api.onMsgDelPush = null;
    _api.onAddLikePush = null;
    _api.onForceLogOut = null;
    _api.onDisconnected = null;
    _api.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
