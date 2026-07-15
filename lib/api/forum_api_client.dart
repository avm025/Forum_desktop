import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/dialog_group.dart';
import '../models/emoji_category.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/user_profile.dart';
import 'api_config.dart';
import 'contacts_service.dart';
import 'device_data_service.dart';
import 'device_id_service.dart';
import 'dialog_mapper.dart';
import 'file_uploader.dart';
import 'forum_network.dart';
import 'message_mapper.dart';
import 'msg_list_request.dart';
import 'msg_list_result.dart';
import 'uploaded_file_info.dart';
import '../services/api_logger.dart';
import '../services/forum_cache.dart';

/// Результат полной инициализации API.
class ForumBootstrapResult {
  final UserProfile profile;
  final List<DialogsListViewModel> dialogs;
  final List<DialogGroup> groups;

  const ForumBootstrapResult({
    required this.profile,
    required this.dialogs,
    required this.groups,
  });
}

/// Push одного сообщения `type: msg` (эхо отправки или входящее).
typedef MsgPushHandler = void Function(Map<String, dynamic> data);

/// Push `msg_list` без ожидающего запроса (новые сообщения с сервера).
typedef MsgListPushHandler = void Function(Map<String, dynamic> data);

/// Push `status` — обновление статусов доставки/прочтения (WS_STATUS.md).
typedef StatusPushHandler = void Function(Map<String, dynamic> data);

/// Push `msg_del` — удаление сообщений в диалоге (WS_MSG_DEL.md).
typedef MsgDelPushHandler = void Function(Map<String, dynamic> data);

/// Push `add_like` — обновление реакций (WS_MSG_LIKES.md).
typedef AddLikePushHandler = void Function(Map<String, dynamic> data);

typedef WsVoidCallback = void Function();

/// Клиент Forum API.
class ForumApiClient {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final http.Client _http = createForumHttpClient();
  final FileUploader _uploader = FileUploader(client: createForumHttpClient());

  MsgPushHandler? onMsgPush;
  MsgListPushHandler? onMsgListPush;
  StatusPushHandler? onStatusPush;
  MsgDelPushHandler? onMsgDelPush;
  AddLikePushHandler? onAddLikePush;
  WsVoidCallback? onDisconnected;

  bool _suppressDisconnect = false;

  bool get isConnected => _channel != null;

  /// Полный цикл: connect → log_in → dlg_list → dlg_grp_list.
  Future<ForumBootstrapResult> bootstrap({String fcmToken = ''}) async {
    final uid = await DeviceIdService.getOrCreate();
    await connect();

    final contactsFuture = ContactsService.loadContacts();
    final profile = await login(uid, fcmToken: fcmToken);
    final contacts = await contactsFuture;

    final dialogsFuture = fetchDialogs(contacts);
    final groupsFuture = fetchGroups();

    return ForumBootstrapResult(
      profile: profile,
      dialogs: await dialogsFuture,
      groups: await groupsFuture,
    );
  }

  Future<UserProfile> login(String uid, {String fcmToken = ''}) async {
    final loginResp = await sendWs({
      'type': 'log_in',
      'data': {
        'uid': uid,
        'token': ApiConfig.token,
      },
    });

    if (loginResp['success'] != true) {
      throw ForumApiException(
        loginResp['message']?.toString() ?? 'Ошибка авторизации',
        payload: loginResp,
      );
    }

    final profileMap =
        Map<String, dynamic>.from(loginResp['profile'] as Map? ?? {});
    await ForumCache.instance.saveProfile(profileMap);

    await sendDeviceData(uid, fcmToken: fcmToken);

    return UserProfile.fromJson(profileMap);
  }

  /// WS `device` после успешного log_in (WS_DEVICE.md).
  Future<void> sendDeviceData(String uid, {String fcmToken = ''}) async {
    if (!isConnected) return;
    if (!await DeviceDataService.shouldSend()) return;

    final data = await DeviceDataService.buildPayload(uid, fcmToken: fcmToken);
    final message = {'type': 'device', 'data': data};

    final channel = _channel;
    if (channel == null) return;

    ApiLogger.instance.logWsSend('device', message);
    channel.sink.add(jsonEncode(message));
    await DeviceDataService.markSent();
  }

  Future<List<DialogsListViewModel>> fetchDialogs(
    List<ApiContact> contacts,
  ) async {
    final dialogsResp = await sendWs({
      'type': 'dlg_list',
      'contacts': contacts.map((c) => c.toJson()).toList(),
    });

    if (dialogsResp['success'] != true) {
      throw ForumApiException(
        dialogsResp['message']?.toString() ?? 'Ошибка загрузки диалогов',
        payload: dialogsResp,
      );
    }

    await ForumCache.instance.saveDialogs(dialogsResp);
    return parseDialogsResponse(dialogsResp);
  }

  Future<List<DialogGroup>> fetchGroups() async {
    final groupsResp = await sendWs({'type': 'dlg_grp_list'});

    if (groupsResp['success'] != true) {
      throw ForumApiException(
        groupsResp['message']?.toString() ?? 'Ошибка загрузки папок',
        payload: groupsResp,
      );
    }

    await ForumCache.instance.saveGroups(groupsResp);
    return parseGroupsResponse(groupsResp);
  }

  List<DialogsListViewModel> parseDialogsResponse(Map<String, dynamic> resp) =>
      _parseDialogs(resp);

  List<DialogGroup> parseGroupsResponse(Map<String, dynamic> resp) =>
      _parseGroups(resp);

  MsgListResult parseMsgListResponse(
    Map<String, dynamic> map, {
    required String expectedDlgId,
    String? currentUserId,
    bool isGroupChat = false,
  }) =>
      _parseMsgListMap(
        map,
        expectedDlgId: expectedDlgId,
        currentUserId: currentUserId,
        isGroupChat: isGroupChat,
      );

  Future<void> connect() async {
    await disconnect();
    ApiLogger.instance.logEvent('WS', 'Подключение ${ApiConfig.wsHost}');
    try {
      final channel = connectForumWebSocket(ApiConfig.wsUri);
      await awaitWebSocketReady(channel);
      _channel = channel;
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _handleSocketClosed(),
        onDone: _handleSocketClosed,
      );
    } catch (e, st) {
      _channel = null;
      ApiLogger.instance.logEvent('WS', 'Handshake ошибка: $e\n$st');
      rethrow;
    }
  }

  void _handleSocketClosed() {
    if (_suppressDisconnect || _channel == null) return;
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    _failAll(StateError('WebSocket соединение закрыто'));
    onDisconnected?.call();
  }

  Future<void> disconnect() async {
    _suppressDisconnect = true;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _failAll(StateError('WebSocket отключён'));
    _suppressDisconnect = false;
  }

  void dispose() {
    onMsgPush = null;
    onMsgListPush = null;
    onStatusPush = null;
    onMsgDelPush = null;
    onAddLikePush = null;
    onDisconnected = null;
    _uploader.close();
    _http.close();
    disconnect();
  }

  /// Загрузка фото/видео перед отправкой WS `msg` type=media.
  Future<UploadedFileInfo> uploadMediaAttachment({
    required Uint8List bytes,
    required String originalName,
  }) =>
      _uploader.uploadMedia(bytes: bytes, originalName: originalName);

  /// Upload media + размеры кадра для body (как в push с сервера).
  Future<MediaUploadResult> uploadMediaWithDimensions({
    required Uint8List bytes,
    required String originalName,
    int duration = 0,
    String width = '',
    String height = '',
  }) =>
      _uploader.uploadMediaWithDimensions(
        bytes: bytes,
        originalName: originalName,
        duration: duration,
        width: width,
        height: height,
      );

  /// Загрузка документа перед отправкой WS `msg` type=file.
  Future<UploadedFileInfo> uploadDocumentAttachment({
    required Uint8List bytes,
    required String originalName,
  }) =>
      _uploader.uploadDocument(bytes: bytes, originalName: originalName);

  /// Отправить чат-сообщение (fire-and-forget). Эхо приходит push `type: msg`.
  void sendMsg(Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) {
      throw StateError('WebSocket не подключён');
    }

    final message = {'type': 'msg', 'data': data};
    final encoded = jsonEncode(message);
    ApiLogger.instance.logWsSend('msg', message);
    channel.sink.add(encoded);
  }

  /// WS `msg_del` — удаление сообщений (WS_MSG_DEL.md). Fire-and-forget.
  void sendMsgDel({
    required String usrId,
    required String dlgId,
    required Object ids,
  }) {
    final channel = _channel;
    if (channel == null || usrId.trim().isEmpty || dlgId.trim().isEmpty) {
      return;
    }

    final message = {
      'type': 'msg_del',
      'data': {
        'usr_id': usrId,
        'dlg_id': dlgId,
        'ids': ids,
      },
    };
    ApiLogger.instance.logWsSend('msg_del', message);
    channel.sink.add(jsonEncode(message));
  }

  /// WS `del_like` — снятие реакции (сервер не toggle'ит повторный `add_like`).
  void sendDelLike({
    required String usrId,
    required String dlgId,
    required String msgId,
    String? emoji,
  }) {
    final channel = _channel;
    if (channel == null ||
        usrId.trim().isEmpty ||
        dlgId.trim().isEmpty ||
        msgId.trim().isEmpty) {
      return;
    }

    final data = <String, dynamic>{
      'usr_id': usrId,
      'dlg_id': dlgId,
      'msg_id': msgId,
    };
    final trimmedEmoji = emoji?.trim();
    if (trimmedEmoji != null && trimmedEmoji.isNotEmpty) {
      data['emoji'] = trimmedEmoji;
    }

    final message = {'type': 'del_like', 'data': data};
    ApiLogger.instance.logWsSend('del_like', message);
    channel.sink.add(jsonEncode(message));
  }

  /// WS `add_like` — реакция на сообщение (WS_MSG_LIKES.md). Fire-and-forget.
  void sendAddLike({
    required String usrId,
    required String emoji,
    required String dlgId,
    required String msgId,
  }) {
    final channel = _channel;
    if (channel == null ||
        usrId.trim().isEmpty ||
        dlgId.trim().isEmpty ||
        msgId.trim().isEmpty ||
        emoji.trim().isEmpty) {
      return;
    }

    final message = {
      'type': 'add_like',
      'data': {
        'usr_id': usrId,
        'emoji': emoji,
        'dlg_id': dlgId,
        'msg_id': msgId,
      },
    };
    ApiLogger.instance.logWsSend('add_like', message);
    channel.sink.add(jsonEncode(message));
  }

  /// WS `dlg_grp` — создание или изменение папки (WS_DLG_GRP.md).
  Future<Map<String, dynamic>> sendDlgGrp({
    String? id,
    String? name,
    String? list,
  }) {
    final data = <String, dynamic>{};
    final trimmedId = id?.trim();
    if (trimmedId != null && trimmedId.isNotEmpty) {
      data['id'] = trimmedId;
    }
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      data['name'] = trimmedName;
    }
    if (list != null) {
      data['list'] = list;
    }
    return sendWs({'type': 'dlg_grp', 'data': data});
  }

  /// WS `dlg_grp_del` — удаление папки (`id` — число).
  Future<Map<String, dynamic>> sendDlgGrpDel(int id) {
    return sendWs({
      'type': 'dlg_grp_del',
      'data': {'id': id},
    });
  }

  /// WS `dlg_grp_sort` — порядок папок.
  Future<Map<String, dynamic>> sendDlgGrpSort(List<String> arr) {
    return sendWs({
      'type': 'dlg_grp_sort',
      'data': {'arr': arr},
    });
  }

  /// HTTP `type: database` — справочники оформления (WS_DATABASE.md).
  Future<Map<String, dynamic>> fetchDatabase() async {
    final sw = Stopwatch()..start();
    const payload = {'type': 'database'};
    final body = jsonEncode(payload);
    ApiLogger.instance.logHttpSend('POST', ApiConfig.httpApiUrl, body);

    final response = await _http
        .post(
          ApiConfig.httpApiUri,
          headers: ApiConfig.authHeaders,
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    sw.stop();
    ApiLogger.instance.logHttpReceive(
      response.statusCode,
      response.body,
      duration: sw.elapsed,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ForumApiException('HTTP ${response.statusCode}: ${response.body}');
    }

    final map = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (map['success'] != true) {
      throw ForumApiException(
        map['message']?.toString() ?? 'Ошибка загрузки справочников',
        payload: map,
      );
    }

    await ForumCache.instance.saveDatabase(map);
    return map;
  }

  /// WS `change_profile` — сохранение оформления в профиле.
  Future<Map<String, dynamic>> changeProfile(Map<String, dynamic> data) async {
    return sendWs({
      'type': 'change_profile',
      'data': data,
    });
  }

  /// HTTP `type: emoji` — справочник emoji для пикера.
  Future<List<EmojiCategory>> fetchEmojiList() async {
    final sw = Stopwatch()..start();
    const payload = {'type': 'emoji'};
    final body = jsonEncode(payload);
    ApiLogger.instance.logHttpSend('POST', ApiConfig.httpApiUrl, body);

    final response = await _http
        .post(
          ApiConfig.httpApiUri,
          headers: ApiConfig.authHeaders,
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    sw.stop();
    ApiLogger.instance.logHttpReceive(
      response.statusCode,
      response.body,
      duration: sw.elapsed,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ForumApiException('HTTP ${response.statusCode}: ${response.body}');
    }

    final map = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (map['success'] != true) {
      throw ForumApiException(
        map['message']?.toString() ?? 'Ошибка загрузки emoji',
        payload: map,
      );
    }

    final data = map['data'];
    if (data is! List) return const [];

    return data
        .whereType<Map>()
        .map((e) => EmojiCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// WS `status` — прочитано / доставлено (WS_STATUS.md). Fire-and-forget.
  void sendStatus({
    required int status,
    required String dlgId,
    required String ids,
  }) {
    final channel = _channel;
    if (channel == null || ids.trim().isEmpty) return;

    final message = {
      'type': 'status',
      'data': {
        'status': status,
        'dlg_id': dlgId,
        'ids': ids,
      },
    };
    ApiLogger.instance.logWsSend('status', message);
    channel.sink.add(jsonEncode(message));
  }

  /// Отправить сообщение по WebSocket и дождаться ответа с тем же type.
  Future<Map<String, dynamic>> sendWs(
    Map<String, dynamic> message, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw StateError('WebSocket не подключён');
    }

    final type = message['type']?.toString();
    if (type == null || type.isEmpty) {
      throw ArgumentError('Поле type обязательно');
    }

    if (_pending.containsKey(type)) {
      throw StateError('Уже ожидается ответ на $type');
    }

    final completer = Completer<Map<String, dynamic>>();
    _pending[type] = completer;
    final sw = Stopwatch()..start();

    try {
      final encoded = jsonEncode(message);
      ApiLogger.instance.logWsSend(type, message);
      channel.sink.add(encoded);
      final resp = await completer.future.timeout(timeout);
      sw.stop();
      ApiLogger.instance.logWsReceive(
        type,
        resp,
        duration: sw.elapsed,
      );
      if (resp['success'] == false && resp['message'] != null) {
        throw ForumApiException(
          resp['message'].toString(),
          payload: resp,
        );
      }
      return resp;
    } on TimeoutException {
      _pending.remove(type);
      rethrow;
    } catch (e) {
      _pending.remove(type);
      rethrow;
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final text = _decodeRaw(raw);
      if (text == null) return;

      final map = Map<String, dynamic>.from(jsonDecode(text) as Map);
      final type = map['type']?.toString();
      if (type == null) return;

      if (map['success'] == false && map['message'] != null) {
        _completeWithError(
          ForumApiException(map['message'].toString(), payload: map),
        );
        return;
      }

      if (type == 'msg') {
        _pending.remove(type);
        final payload = _extractMsgPayload(map);
        if (payload != null) {
          ApiLogger.instance.logWsReceive(type, map);
          onMsgPush?.call(payload);
        }
        return;
      }

      if (type == 'msg_list') {
        final completer = _pending.remove(type);
        if (completer != null && !completer.isCompleted) {
          completer.complete(map);
        } else {
          final data = map['data'];
          if (data is Map) {
            ApiLogger.instance.logWsReceive(type, map);
            onMsgListPush?.call(Map<String, dynamic>.from(data));
          }
        }
        return;
      }

      if (type == 'status') {
        _pending.remove(type);
        final data = map['data'];
        if (data is Map) {
          ApiLogger.instance.logWsReceive(type, map);
          onStatusPush?.call(Map<String, dynamic>.from(data));
        }
        return;
      }

      if (type == 'msg_del') {
        _pending.remove(type);
        ApiLogger.instance.logWsReceive(type, map);
        onMsgDelPush?.call(map);
        return;
      }

      if (type == 'add_like' || type == 'del_like') {
        _pending.remove(type);
        ApiLogger.instance.logWsReceive(type, map);
        onAddLikePush?.call(map);
        return;
      }

      final completer = _pending.remove(type);
      if (completer != null && !completer.isCompleted) {
        completer.complete(map);
      } else if (type != 'dlg_list' && type != 'dlg_grp_list') {
        ApiLogger.instance.logWsReceive(type, map);
      }
    } catch (e, st) {
      ApiLogger.instance.logEvent('WS', 'Ошибка разбора: $e\n$st');
    }
  }

  static String? _decodeRaw(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List<int>) return utf8.decode(raw);
    return raw?.toString();
  }

  /// Push `msg`: поля в `data` или на верхнем уровне.
  static Map<String, dynamic>? _extractMsgPayload(Map<String, dynamic> map) {
    final data = map['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    final hasMsgFields = map.containsKey('dlg_id') ||
        map.containsKey('id') ||
        map.containsKey('body') ||
        map.containsKey('hash');
    if (!hasMsgFields) return null;

    final copy = Map<String, dynamic>.from(map);
    for (final key in ['type', 'success', 'message']) {
      copy.remove(key);
    }
    return copy;
  }

  void _completeWithError(ForumApiException error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
  }

  void _failAll(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
  }

  List<DialogsListViewModel> _parseDialogs(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is! Map) return const [];

    final raw = data['dialogs'];
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((e) => DialogMapper.fromServerJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<DialogGroup> _parseGroups(Map<String, dynamic> resp) {
    final raw = _extractGroupsList(resp['data']);
    if (raw == null) return const [];

    return raw
        .whereType<Map>()
        .map((e) => DialogGroup.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
  }

  static List<dynamic>? _extractGroupsList(dynamic data) {
    if (data is List) return data;
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> _msgListPayload(String dlgId, MsgListRequest request) {
    final data = <String, dynamic>{'dlg_id': dlgId};
    if (request.getNew) {
      data['last_id'] = request.lastId ?? '0';
      data['last_dt'] = request.lastDt ?? '';
    } else {
      data['first_id'] = request.firstId ?? '0';
    }
    return {
      'type': 'msg_list',
      'data': data,
    };
  }

  /// msg_list по WS_MSG_LIST.md — WebSocket основной, HTTP запасной.
  Future<MsgListResult> fetchMessageList(
    String dlgId, {
    required MsgListRequest request,
    String? currentUserId,
    bool isGroupChat = false,
  }) async {
    final payload = _msgListPayload(dlgId, request);
    Map<String, dynamic> map;

    if (isConnected) {
      try {
        map = await sendWs(payload);
      } catch (_) {
        map = await _fetchMessageListHttpMap(payload);
      }
    } else {
      map = await _fetchMessageListHttpMap(payload);
    }

    if (!request.getNew) {
      await ForumCache.instance.saveMessages(dlgId, map);
    }

    return _parseMsgListMap(
      map,
      expectedDlgId: dlgId,
      currentUserId: currentUserId,
      isGroupChat: isGroupChat,
    );
  }

  Future<Map<String, dynamic>> _fetchMessageListHttpMap(
    Map<String, dynamic> payload,
  ) async {
    final body = jsonEncode(payload);
    final sw = Stopwatch()..start();
    ApiLogger.instance.logHttpSend('POST', ApiConfig.httpApiUrl, body);

    final response = await _http
        .post(
          ApiConfig.httpApiUri,
          headers: ApiConfig.authHeaders,
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    sw.stop();
    ApiLogger.instance.logHttpReceive(
      response.statusCode,
      response.body,
      duration: sw.elapsed,
    );

    if (response.statusCode == 401) {
      throw ForumApiException('401: ${response.body}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ForumApiException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final map = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (map['success'] != true) {
      throw ForumApiException(
        map['message']?.toString() ?? 'Ошибка загрузки сообщений',
        payload: map,
      );
    }
    return map;
  }

  MsgListResult _parseMsgListMap(
    Map<String, dynamic> map, {
    required String expectedDlgId,
    String? currentUserId,
    bool isGroupChat = false,
  }) {
    if (map['success'] == false) {
      throw ForumApiException(
        map['message']?.toString() ?? 'Ошибка загрузки сообщений',
        payload: map,
      );
    }

    final dataMap = map['data'];
    if (dataMap is! Map) {
      return MsgListResult.empty;
    }

    final data = Map<String, dynamic>.from(dataMap);
    final responseDlgId = data['dlg_id']?.toString();
    if (responseDlgId != null &&
        responseDlgId.isNotEmpty &&
        responseDlgId != expectedDlgId) {
      throw ForumApiException(
        'dlg_id в ответе ($responseDlgId) не совпадает с запрошенным ($expectedDlgId)',
        payload: map,
      );
    }

    final raw = data['msgs'];
    if (raw is! List) {
      return MsgListResult.empty;
    }

    if (raw.isNotEmpty && map.containsKey('success')) {
      final first = raw.first;
      if (first is Map) {
        final msgDlgId = first['dlg_id']?.toString();
        if (msgDlgId != null &&
            msgDlgId.isNotEmpty &&
            msgDlgId != expectedDlgId) {
          throw ForumApiException(
            'msgs[0].dlg_id ($msgDlgId) не совпадает с запрошенным ($expectedDlgId)',
            payload: map,
          );
        }
      }
    }

    final messages = MessageMapper.fromMsgList(
      raw,
      currentUserId: currentUserId,
      isGroupChat: isGroupChat,
    );

    final responseFirstId = data['first_id']?.toString();
    final isHistory = data.containsKey('first_id');
    final hasMoreHistory =
        isHistory && messages.length >= MsgListResult.historyPageSize;

    return MsgListResult(
      messages: messages,
      isHistory: isHistory,
      responseFirstId:
          responseFirstId != null && responseFirstId.isNotEmpty
              ? responseFirstId
              : null,
      hasMoreHistory: hasMoreHistory,
    );
  }
}

class ForumApiException implements Exception {
  final String message;
  final Map<String, dynamic>? payload;

  ForumApiException(this.message, {this.payload});

  @override
  String toString() => message;
}
