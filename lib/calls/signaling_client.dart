import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_config.dart';
import '../api/forum_network.dart';
import '../services/api_logger.dart';
import 'call_models.dart';

/// WebSocket control-plane звонков (iOS `SignalingClient.swift`).
///
/// Очередь исходящих до `auth.ok`, иначе invite / `push.register` уходят
/// неавторизованными (как в логе `unauthenticated`).
class CallSignalingClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _wantConnected = false;
  bool _authenticated = false;
  bool _opening = false;
  String? _authToken;
  String? _pushToken;
  String? _authedUserId;
  int _reconnectAttempt = 0;
  Completer<void>? _authCompleter;

  final _outboundQueue = <Map<String, dynamic>>[];
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get isConnected => _channel != null;
  bool get isAuthenticated => _authenticated;
  String? get authenticatedUserId => _authedUserId;

  Future<void> connect({required String sessionToken}) async {
    _wantConnected = true;
    _authToken = sessionToken.trim();
    if (_authToken == null || _authToken!.isEmpty) return;
    await _open();
  }

  /// Ждёт реальный `auth.ok` (без фейкового fallback).
  Future<void> waitUntilAuthenticated({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_authenticated) return;
    if (!_wantConnected) {
      throw StateError('signaling not connecting');
    }
    // На паузе между reconnect completer может быть null — подождём _open.
    final deadline = DateTime.now().add(timeout);
    while (!_authenticated) {
      final c = _authCompleter;
      if (c != null) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('auth.ok timeout');
        }
        try {
          await c.future.timeout(remaining);
        } catch (_) {
          if (_authenticated) return;
          if (DateTime.now().isAfter(deadline)) rethrow;
          // Reconnect создаст новый completer — цикл продолжит.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('auth.ok timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _authenticated = false;
    _authedUserId = null;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _failAuthWait(StateError('disconnected'));
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    unawaited(_events.close());
  }

  /// iOS: `push.register{voipToken}`; Android/desktop: `{fcmToken}`.
  void registerVoipToken(String token) {
    _pushToken = token.trim();
    if (_pushToken == null || _pushToken!.isEmpty) return;
    _send(_pushRegisterPayload(_pushToken!));
  }

  void sendInvite({
    required String calleeId,
    required bool video,
    String? dlgId,
    String? callId,
  }) {
    // 1:1 без group/groupId сервер не шлёт caller'у call.token/callId
    // (только callee видит ring). С groupId=dlgId получаем call.token сразу,
    // иначе hangup до соединения нечем адресовать.
    final groupKey =
        (dlgId != null && dlgId.trim().isNotEmpty) ? dlgId.trim() : calleeId;
    _send({
      'type': 'call.invite',
      'payload': {
        'callees': [calleeId],
        'video': video,
        'media': video ? 'video' : 'audio',
        'group': true,
        'groupId': groupKey,
        if (dlgId != null && dlgId.isNotEmpty) 'dlgId': dlgId,
        if (callId != null &&
            callId.isNotEmpty &&
            callId != 'pending')
          'callId': callId,
      },
    });
  }

  void sendGroupInvite({
    required List<String> participantIds,
    required bool video,
    String? groupId,
    String? dlgId,
    String? title,
    String? callId,
  }) {
    _send({
      'type': 'call.invite',
      'payload': {
        'callees': participantIds,
        'video': video,
        'media': video ? 'video' : 'audio',
        'group': true,
        if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
        if (dlgId != null && dlgId.isNotEmpty) 'dlgId': dlgId,
        if (title != null && title.isNotEmpty) 'title': title,
        if (callId != null &&
            callId.isNotEmpty &&
            callId != 'pending')
          'callId': callId,
      },
    });
  }

  void sendInviteToCall({
    required String callId,
    required List<String> callees,
    required bool video,
    String? groupId,
  }) {
    if (callId.isEmpty || callId == 'pending' || callees.isEmpty) return;
    _send({
      'type': 'call.invite',
      'callId': callId,
      'payload': {
        'callees': callees,
        'video': video,
        'media': video ? 'video' : 'audio',
        if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
        'group': true,
      },
    });
  }

  void sendAccept({required String callId, required bool video}) {
    _send({
      'type': 'call.accept',
      'callId': callId,
      'payload': {
        'video': video,
        'media': video ? 'video' : 'audio',
      },
    });
  }

  void sendCancel({
    required String callId,
    String? dlgId,
    List<String>? callees,
  }) {
    if (callId.isEmpty || callId == 'pending') return;
    final peers =
        callees?.where((e) => e.trim().isNotEmpty).toList() ?? const [];
    _send({
      'type': 'call.cancel',
      'callId': callId,
      'payload': <String, dynamic>{
        if (dlgId != null && dlgId.isNotEmpty) 'dlgId': dlgId,
        if (peers.isNotEmpty) 'callees': peers,
      },
    });
  }

  void sendReject({
    required String callId,
    String? dlgId,
    List<String>? callees,
  }) {
    final peers =
        callees?.where((e) => e.trim().isNotEmpty).toList() ?? const [];
    _send({
      'type': 'call.reject',
      'callId': callId,
      'payload': <String, dynamic>{
        if (dlgId != null && dlgId.isNotEmpty) 'dlgId': dlgId,
        if (peers.isNotEmpty) 'callees': peers,
      },
    });
  }

  void sendHangup({
    required String callId,
    List<String>? callees,
    String? dlgId,
  }) {
    final hasId = callId.isNotEmpty && callId != 'pending';
    final peers = callees?.where((e) => e.trim().isNotEmpty).toList() ?? const [];
    if (!hasId && peers.isEmpty && (dlgId == null || dlgId.isEmpty)) return;
    _send({
      'type': 'call.hangup',
      if (hasId) 'callId': callId,
      'payload': {
        if (peers.isNotEmpty) 'callees': peers,
        if (dlgId != null && dlgId.isNotEmpty) 'dlgId': dlgId,
      },
    });
  }

  void sendRecordStart({required String callId}) {
    _send({
      'type': 'call.record.start',
      'callId': callId,
      'payload': <String, dynamic>{},
    });
  }

  void sendRecordStop({required String callId}) {
    _send({
      'type': 'call.record.stop',
      'callId': callId,
      'payload': <String, dynamic>{},
    });
  }

  Map<String, dynamic> _pushRegisterPayload(String token) => {
        'type': 'push.register',
        'payload': {
          'voipToken': token,
          'fcmToken': token,
          'platform': 'desktop',
        },
      };

  Future<void> _open() async {
    if (_disposed || !_wantConnected || _opening) return;
    _opening = true;
    await _sub?.cancel();
    _pingTimer?.cancel();
    _authenticated = false;
    _authedUserId = null;
    _failAuthWait(StateError('reconnecting'));
    _authCompleter = Completer<void>();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    final token = _authToken ?? '';
    final uri = ApiConfig.callSignalingUriForToken(token);
    ApiLogger.instance.logEvent(
      'CALL_SIG',
      'connect ${uri.scheme}://${uri.host}:${uri.port}${uri.path}',
    );
    try {
      final channel = await connectCallSignalingWebSocket(
        uri,
        headers: const {'Origin': 'https://4um.me'},
      ).timeout(const Duration(seconds: 15));

      if (_disposed || !_wantConnected) {
        try {
          await channel.sink.close();
        } catch (_) {}
        return;
      }

      _channel = channel;
      _reconnectAttempt = 0;

      _sub = channel.stream.listen(
        _onData,
        onError: (Object e, StackTrace st) {
          ApiLogger.instance.logEvent('CALL_SIG', 'error: $e');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );

      // Явное auth: {"type":"auth","payload":{"token":...}} → auth.ok
      _sendRaw({
        'type': 'auth',
        'payload': {'token': token},
      });
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        if (_authenticated) _sendRaw({'type': 'ping'});
      });
    } catch (e) {
      ApiLogger.instance.logEvent('CALL_SIG', 'open failed: $e');
      _channel = null;
      _failAuthWait(e);
      _scheduleReconnect();
    } finally {
      _opening = false;
    }
  }

  void _scheduleReconnect() {
    _authenticated = false;
    _authedUserId = null;
    _channel = null;
    _pingTimer?.cancel();
    _failAuthWait(StateError('connection lost'));
    if (!_wantConnected || _disposed) return;
    _reconnectTimer?.cancel();
    final delaySec = (1 << _reconnectAttempt.clamp(0, 4)).clamp(3, 30);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      unawaited(_open());
    });
  }

  void _onData(dynamic raw) {
    try {
      final text = raw is String ? raw : raw?.toString();
      if (text == null || text.isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      ApiLogger.instance.logWsReceive('call_sig', map);

      final type = map['type']?.toString() ?? '';
      if (_isAuthOk(map)) {
        _onAuthenticated(map);
      } else if (type == 'error') {
        final payload = map['payload'];
        final code = payload is Map
            ? payload['code']?.toString()
            : map['code']?.toString();
        if (code == 'unauthenticated' || code == 'auth_failed') {
          ApiLogger.instance.logEvent('CALL_SIG', 'auth required: $map');
          if (!_authenticated) {
            // Повторный auth (invite не должен уходить до auth.ok).
            final token = _authToken;
            if (token != null && token.isNotEmpty) {
              _sendRaw({
                'type': 'auth',
                'payload': {'token': token},
              });
            }
          } else {
            // Сессия на сервере сброшена — переподключение.
            _authenticated = false;
            _scheduleReconnect();
          }
        }
      }

      if (!_events.isClosed) _events.add(map);
    } catch (e) {
      ApiLogger.instance.logEvent('CALL_SIG', 'parse: $e');
    }
  }

  bool _isAuthOk(Map<String, dynamic> map) {
    final type = map['type']?.toString() ?? '';
    if (type == 'auth.ok') return true;
    if (type == 'auth') {
      if (map['success'] == true || map['ok'] == true) return true;
      final payload = map['payload'];
      if (payload is Map &&
          (payload['ok'] == true || payload['success'] == true)) {
        return true;
      }
    }
    return false;
  }

  void _onAuthenticated(Map<String, dynamic> map) {
    if (_authenticated) return;
    _authenticated = true;
    _authedUserId = _extractUserId(map);
    final who = _authedUserId ?? '?';
    ApiLogger.instance.logEvent(
      'CALL',
      'сигнализация авторизована как $who',
    );

    final c = _authCompleter;
    if (c != null && !c.isCompleted) c.complete();

    // Как iOS: flushPendingVoIPToken after auth.ok
    if (_pushToken != null && _pushToken!.isNotEmpty) {
      ApiLogger.instance.logEvent(
        'CALL',
        'flushPendingVoIPToken after auth.ok',
      );
      _sendRaw(_pushRegisterPayload(_pushToken!));
    }

    final queued = List<Map<String, dynamic>>.from(_outboundQueue);
    _outboundQueue.clear();
    for (final msg in queued) {
      _sendRaw(msg);
    }
  }

  String? _extractUserId(Map<String, dynamic> map) {
    final payload = map['payload'];
    final fromPayload = payload is Map
        ? (payload['userId'] ??
                payload['user_id'] ??
                payload['usr_id'] ??
                payload['id'] ??
                payload['i'])
            ?.toString()
        : null;
    final direct = (map['userId'] ??
            map['user_id'] ??
            map['usr_id'] ??
            map['id'] ??
            map['i'] ??
            map['user'])
        ?.toString();
    final id = (fromPayload ?? direct)?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  void _failAuthWait(Object error) {
    final c = _authCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(error);
    }
    _authCompleter = null;
  }

  void _send(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    if (!_authenticated && type != 'auth' && type != 'ping') {
      _outboundQueue.add(message);
      ApiLogger.instance.logEvent(
        'CALL_SIG',
        'queued $type until auth.ok (queue=${_outboundQueue.length})',
      );
      return;
    }
    _sendRaw(message);
  }

  void _sendRaw(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      ApiLogger.instance.logWsSend('call_sig', message);
      channel.sink.add(jsonEncode(message));
    } catch (e) {
      ApiLogger.instance.logEvent('CALL_SIG', 'send failed: $e');
    }
  }
}

IncomingCallInvite? parseIncomingInvite(Map<String, dynamic> map) {
  final type = map['type']?.toString() ?? '';
  if (type != 'invite' &&
      type != 'incoming' &&
      type != 'call.invite' &&
      type != 'call.ring' &&
      type != 'incoming_call') {
    return null;
  }

  final payload = map['payload'];
  final body = payload is Map
      ? Map<String, dynamic>.from(payload)
      : map;

  final callId = (map['callId'] ??
              map['call_id'] ??
              body['callId'] ??
              body['call_id'] ??
              map['id'])
          ?.toString()
          .trim() ??
      '';
  if (callId.isEmpty) return null;

  final callerId = (body['callerId'] ??
              body['caller_id'] ??
              body['fr_id'] ??
              body['from'] ??
              body['usr_id'] ??
              map['caller_id'])
          ?.toString()
          .trim() ??
      '';
  final video = body['video'] == true ||
      body['video'] == 1 ||
      body['media']?.toString() == 'video' ||
      map['video'] == true;
  final isGroup = body['group'] == true ||
      body['isGroup'] == true ||
      body['is_group'] == true ||
      (body['groupId']?.toString().isNotEmpty == true);

  return IncomingCallInvite(
    callId: callId,
    callerId: callerId,
    callerName: (body['callerName'] ??
                body['caller_name'] ??
                body['name'] ??
                body['fr_name'])
            ?.toString() ??
        '',
    callerAvatar: (body['callerAva'] ??
                body['caller_ava'] ??
                body['ava'] ??
                body['avatar'])
            ?.toString() ??
        '',
    video: video,
    isGroup: isGroup,
    groupId: (body['groupId'] ?? body['group_id'])?.toString(),
    dlgId: (body['dlgId'] ?? body['dlg_id'])?.toString(),
    title: body['title']?.toString() ?? '',
    e2eeEnabled: parseCallE2eeFlag(map),
  );
}
