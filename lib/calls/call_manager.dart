import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../services/api_logger.dart';
import 'call_models.dart';
import 'signaling_client.dart';

/// Оркестрация 1:1 и групповых звонков (iOS `CallManager.shared`).
class CallManager extends ChangeNotifier {
  CallManager._();
  static final CallManager instance = CallManager._();

  final CallSignalingClient _signaling = CallSignalingClient();
  StreamSubscription? _sigSub;

  /// Локальная вставка msg type=call в чат (сервер тоже шлёт — дедуп по call_id).
  void Function(CallChatResult result)? onCallChatResult;

  CallSession? _session;
  IncomingCallInvite? _incoming;
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  bool _micEnabled = true;
  bool _camEnabled = false;
  bool _speakerOn = true;
  bool _invitePickerOpen = false;
  /// Пользователь нажал «Завершить» до call.token / LiveKit — отменим, как только будет callId.
  bool _endRequested = false;
  /// Локальное завершение в процессе — не эмитить chat-result из RoomDisconnected.
  bool _localEnding = false;
  bool _chatResultSent = false;
  DateTime? _connectedAt;
  /// Собеседник принял / зашёл в комнату. LiveKit у caller поднимается сразу —
  /// это ещё не «отвеченный» звонок (иначе уходит hangup→talk вместо cancel).
  bool _remoteAccepted = false;
  String? _localUserId;
  String? _localUserName;
  /// Контекст завершения после очистки session (deferred cancel/hangup).
  _DeferredCallEnd? _deferredEnd;

  CallSession? get session => _session;
  IncomingCallInvite? get incoming => _incoming;
  Room? get room => _room;
  bool get micEnabled => _micEnabled;
  bool get camEnabled => _camEnabled;
  bool get speakerOn => _speakerOn;
  bool get invitePickerOpen => _invitePickerOpen;
  /// Сквозное шифрование медиа (call_e2ee.md / iOS CallManager.isE2EEEnabled).
  bool get isE2EEEnabled => _session?.e2eeEnabled == true;
  bool get hasActiveCall =>
      _session != null &&
      _session!.state != CallState.idle &&
      _session!.state != CallState.ended &&
      _session!.state != CallState.failed;

  Future<void> configure({
    required String userId,
    required String userName,
    required String sessionToken,
  }) async {
    _localUserId = userId.trim();
    _localUserName = userName.trim();
    await _sigSub?.cancel();
    _sigSub = _signaling.events.listen(_onSignalingEvent);
    await _signaling.connect(sessionToken: sessionToken);
    try {
      await _signaling.waitUntilAuthenticated();
    } catch (e) {
      ApiLogger.instance.logEvent('CALL', 'auth wait failed: $e');
    }
  }

  Future<void> _ensureSignalingAuth() async {
    if (_signaling.isAuthenticated) return;
    await _signaling.waitUntilAuthenticated(
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> shutdown() async {
    onCallChatResult = null;
    await hangup(local: true);
    await _signaling.disconnect();
  }

  void registerVoipToken(String token) => _signaling.registerVoipToken(token);

  bool get canInviteParticipants {
    final s = _session;
    if (s == null) return false;
    if (s.callId.isEmpty || s.callId == 'pending') return false;
    return s.state == CallState.ringing ||
        s.state == CallState.connectingMedia ||
        s.state == CallState.active;
  }

  void openInvitePicker() {
    if (!canInviteParticipants) return;
    _invitePickerOpen = true;
    notifyListeners();
  }

  void closeInvitePicker() {
    if (!_invitePickerOpen) return;
    _invitePickerOpen = false;
    notifyListeners();
  }

  /// Добавить участников в текущий звонок (iOS `inviteToGroup`).
  void inviteParticipants(List<CallParticipant> people) {
    final s = _session;
    if (s == null || !canInviteParticipants) return;
    final existing = s.peers.map((p) => p.userId.trim()).toSet();
    if (_localUserId != null) existing.add(_localUserId!);
    final fresh = <CallParticipant>[];
    final ids = <String>[];
    for (final p in people) {
      final id = p.userId.trim();
      if (id.isEmpty || existing.contains(id)) continue;
      fresh.add(p);
      ids.add(id);
      existing.add(id);
    }
    if (ids.isEmpty) {
      closeInvitePicker();
      return;
    }

    _signaling.sendInviteToCall(
      callId: s.callId,
      callees: ids,
      video: s.wantsVideo || _camEnabled,
      groupId: s.groupId ?? s.dlgId,
    );
    _session = s.copyWith(
      isGroup: true,
      peers: [...s.peers, ...fresh],
    );
    _invitePickerOpen = false;
    notifyListeners();
    ApiLogger.instance.logEvent(
      'CALL',
      'invite participants ${ids.length} → call ${s.callId}',
    );
  }

  /// 1:1 исходящий.
  Future<void> startCall({
    required String peerId,
    required String peerName,
    String peerAvatar = '',
    String? dlgId,
    required bool video,
  }) async {
    if (hasActiveCall) return;
    try {
      await _ensureSignalingAuth();
    } catch (e) {
      ApiLogger.instance.logEvent('CALL', 'invite blocked, no auth: $e');
      return;
    }
    _endRequested = false;
    _localEnding = false;
    _deferredEnd = null;
    _chatResultSent = false;
    _connectedAt = null;
    _remoteAccepted = false;
    const callId = 'pending';
    _incoming = null;
    _micEnabled = true;
    _camEnabled = video;
    _session = CallSession(
      callId: callId,
      direction: CallDirection.outgoing,
      mediaType: video ? CallMediaType.video : CallMediaType.audio,
      dlgId: dlgId,
      title: peerName,
      peers: [
        CallParticipant(
          userId: peerId,
          name: peerName,
          avatarUrl: peerAvatar,
        ),
      ],
      state: CallState.ringing,
    );
    notifyListeners();
    _signaling.sendInvite(
      calleeId: peerId,
      video: video,
      dlgId: dlgId,
    );
  }

  /// Групповой исходящий.
  Future<void> startGroupCall({
    required List<CallParticipant> participants,
    required String groupId,
    required String title,
    String? dlgId,
    required bool video,
  }) async {
    if (hasActiveCall) return;
    try {
      await _ensureSignalingAuth();
    } catch (e) {
      ApiLogger.instance.logEvent('CALL', 'group invite blocked, no auth: $e');
      return;
    }
    _endRequested = false;
    _localEnding = false;
    _deferredEnd = null;
    _chatResultSent = false;
    _connectedAt = null;
    _remoteAccepted = false;
    const callId = 'pending';
    final ids = participants
        .map((p) => p.userId.trim())
        .where((e) => e.isNotEmpty && e != _localUserId)
        .toList();
    if (ids.isEmpty) return;

    _incoming = null;
    _micEnabled = true;
    _camEnabled = video;
    _session = CallSession(
      callId: callId,
      direction: CallDirection.outgoing,
      mediaType: video ? CallMediaType.video : CallMediaType.audio,
      isGroup: true,
      groupId: groupId,
      dlgId: dlgId,
      title: title,
      peers: participants,
      state: CallState.ringing,
    );
    notifyListeners();
    _signaling.sendGroupInvite(
      participantIds: ids,
      video: video,
      groupId: groupId,
      dlgId: dlgId,
      title: title,
    );
  }

  Future<void> acceptIncoming({bool withVideo = false}) async {
    final invite = _incoming;
    if (invite == null) return;
    _endRequested = false;
    _localEnding = false;
    _deferredEnd = null;
    _chatResultSent = false;
    _connectedAt = null;
    // Входящий: приняли сами — для hangup/talk это уже «отвеченный» звонок.
    _remoteAccepted = true;
    _incoming = null;
    _micEnabled = true;
    _camEnabled = withVideo || invite.video;
    _session = CallSession(
      callId: invite.callId,
      direction: CallDirection.incoming,
      mediaType: (withVideo || invite.video)
          ? CallMediaType.video
          : CallMediaType.audio,
      isGroup: invite.isGroup,
      groupId: invite.groupId,
      dlgId: invite.dlgId,
      title: invite.title.isNotEmpty ? invite.title : invite.callerName,
      peers: [
        CallParticipant(
          userId: invite.callerId,
          name: invite.callerName,
          avatarUrl: invite.callerAvatar,
        ),
      ],
      state: CallState.connectingMedia,
      e2eeEnabled: invite.e2eeEnabled,
    );
    notifyListeners();
    _signaling.sendAccept(callId: invite.callId, video: _camEnabled);
  }

  void declineIncoming() {
    final invite = _incoming;
    if (invite == null) return;
    final me = _localUserId ?? '';
    _signaling.sendReject(
      callId: invite.callId,
      dlgId: invite.dlgId ?? invite.groupId,
    );
    _emitCallChatResult(
      CallChatResult(
        dlgId: invite.dlgId ?? invite.groupId,
        callId: invite.callId,
        media: invite.video ? 'video' : 'audio',
        type: 'cancelled',
        rejectUsrId: me,
        callerId: invite.callerId,
        callerName: invite.callerName,
        outgoing: false,
        peerUserId: invite.callerId,
      ),
    );
    _incoming = null;
    notifyListeners();
  }

  Future<void> hangup({bool local = true}) async {
    final session = _session;
    _invitePickerOpen = false;
    CallChatResult? chatResult;
    if (session != null && local) {
      _localEnding = true;
      chatResult = _resultForLocalHangup(session);
      // Сразу в чат — до leaveRoom, иначе RoomDisconnected может перебить тип.
      _emitCallChatResult(chatResult);
      chatResult = null;

      final peers = session.peers
          .map((p) => p.userId.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final dlgId = session.dlgId ?? session.groupId;
      final answered = _isAnswered(session);
      final preferCancel =
          !answered && session.direction == CallDirection.outgoing;
      final callId = session.callId.trim();
      final hasCallId = callId.isNotEmpty && callId != 'pending';

      _deferredEnd = _DeferredCallEnd(
        preferCancel: preferCancel,
        peers: peers,
        dlgId: dlgId,
        callId: hasCallId ? callId : null,
      );

      if (preferCancel) {
        // Только cancel: hangup до ответа сервер пишет как talk (duration:0).
        if (hasCallId) {
          _endRequested = false;
          _signaling.sendCancel(
            callId: callId,
            dlgId: dlgId,
            callees: peers,
          );
          ApiLogger.instance.logEvent(
            'CALL',
            'outgoing cancel callId=$callId peers=${peers.length}',
          );
        } else {
          _endRequested = true;
          // Без callId — мягкий hangup по callees; cancel дошлём в deferred.
          _signaling.sendHangup(
            callId: 'pending',
            callees: peers,
            dlgId: dlgId,
          );
        }
      } else if (!hasCallId) {
        _endRequested = true;
        _signaling.sendHangup(
          callId: 'pending',
          callees: peers,
          dlgId: dlgId,
        );
      } else {
        _endRequested = false;
        _signaling.sendHangup(
          callId: callId,
          callees: peers,
          dlgId: dlgId,
        );
      }
    } else if (local) {
      _endRequested = false;
      _deferredEnd = null;
    }

    await _leaveRoom();
    if (_session != null) {
      _session = _session!.copyWith(state: CallState.ended);
      notifyListeners();
      _session = null;
      notifyListeners();
    }
    if (chatResult != null) _emitCallChatResult(chatResult);
    if (!_endRequested) {
      _deferredEnd = null;
      _localEnding = false;
    }
  }

  /// Исходящий «отвечен» только когда remote принял; LiveKit у caller — не критерий.
  bool _isAnswered(CallSession session) {
    if (session.direction == CallDirection.outgoing) {
      return _remoteAccepted;
    }
    return _remoteAccepted ||
        session.state == CallState.active ||
        (_room != null && _connectedAt != null);
  }

  void _markRemoteAccepted() {
    if (_remoteAccepted) return;
    _remoteAccepted = true;
    _connectedAt ??= DateTime.now();
    if (_session != null &&
        _session!.state != CallState.ended &&
        _session!.state != CallState.failed) {
      _session = _session!.copyWith(state: CallState.active);
    }
    ApiLogger.instance.logEvent('CALL', 'remote accepted / joined');
    notifyListeners();
  }

  /// Отмена/завершение на сервере после появления callId (session может быть уже null).
  void _hangupCallOnServer(String callId) {
    if (callId.isEmpty || callId == 'pending') return;
    final deferred = _deferredEnd;
    final dlgId =
        deferred?.dlgId ?? _session?.dlgId ?? _session?.groupId;
    final peers = deferred?.peers ??
        _session?.peers
            .map((p) => p.userId.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final preferCancel = deferred?.preferCancel == true ||
        (_session != null &&
            !_isAnswered(_session!) &&
            _session!.direction == CallDirection.outgoing);

    if (preferCancel) {
      // Не слать hangup — иначе сервер call_msg type=talk.
      _signaling.sendCancel(
        callId: callId,
        dlgId: dlgId,
        callees: peers,
      );
    } else {
      _signaling.sendHangup(
        callId: callId,
        callees: peers,
        dlgId: dlgId,
      );
    }
    ApiLogger.instance.logEvent(
      'CALL',
      'server end callId=$callId cancel=$preferCancel peers=${peers.length}',
    );
  }

  /// Если пришёл callId после локальной отмены — дослать cancel/hangup.
  void _flushDeferredEndIfNeeded(String? callId) {
    if (!_endRequested) return;
    final id = (callId ?? _deferredEnd?.callId)?.trim();
    if (id == null || id.isEmpty || id == 'pending') return;
    _deferredEnd = (_deferredEnd ??
            const _DeferredCallEnd(preferCancel: true, peers: []))
        .copyWith(callId: id);
    _hangupCallOnServer(id);
    _endRequested = false;
    _deferredEnd = null;
    _localEnding = false;
  }

  Future<void> toggleMute() async {
    _micEnabled = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _camEnabled = !_camEnabled;
    await _room?.localParticipant?.setCameraEnabled(_camEnabled);
    final s = _session;
    if (s != null && _camEnabled) {
      _session = s.copyWith(mediaType: CallMediaType.video);
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    // Desktop: системный вывод; на мобильных — HardwareKeyboard / native.
    try {
      await Hardware.instance.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final track = _room?.localParticipant?.videoTrackPublications
        .where((p) => p.track != null)
        .map((p) => p.track)
        .whereType<LocalVideoTrack>()
        .firstOrNull;
    if (track == null) return;
    try {
      final devices = await Hardware.instance.enumerateDevices();
      final cams =
          devices.where((d) => d.kind == 'videoinput').toList(growable: false);
      if (cams.length < 2) return;
      final current = track.currentOptions.deviceId;
      final next = cams.firstWhere(
        (d) => d.deviceId != current,
        orElse: () => cams.first,
      );
      await track.switchCamera(next.deviceId);
    } catch (e) {
      ApiLogger.instance.logEvent('CALL', 'switchCamera: $e');
    }
  }

  void toggleRecording() {
    final s = _session;
    if (s == null || s.state != CallState.active) return;
    if (s.recording) {
      _signaling.sendRecordStop(callId: s.callId);
    } else {
      _signaling.sendRecordStart(callId: s.callId);
    }
  }

  /// Входящий из FCM / PushKit payload.
  void handlePushPayload(Map<String, dynamic> data) {
    final invite = parseIncomingInvite(data) ??
        parseIncomingInvite({
          ...data,
          'type': data['type'] ?? 'incoming',
        });
    if (invite == null) return;
    _presentIncoming(invite);
  }

  void _onSignalingEvent(Map<String, dynamic> map) {
    final type = map['type']?.toString() ?? '';

    if (type == 'pong' || type == 'auth.ok' || type == 'push.register') return;
    if (type == 'auth' && map['success'] != false) return;

    // Любое call.* с callId — привязать к исходящему pending (и сбросить deferred hangup).
    if (_maybeBindCallId(map)) return;

    final invite = parseIncomingInvite(map);
    if (invite != null &&
        (_session == null || _session!.callId != invite.callId)) {
      // Исходящий echo invite игнорируем.
      if (_session?.direction == CallDirection.outgoing &&
          (_session?.callId == invite.callId ||
              _session?.callId == 'pending')) {
        if (_session!.callId == 'pending' && invite.callId.isNotEmpty) {
          _session = _session!.copyWith(callId: invite.callId);
          notifyListeners();
        }
        return;
      }
      if (invite.callerId.isNotEmpty &&
          invite.callerId == _localUserId) {
        return;
      }
      _presentIncoming(invite);
      return;
    }

    if (type == 'call.token' || type == 'token' || type == 'media') {
      if (_endRequested) {
        _flushDeferredEndIfNeeded(_extractCallId(map));
        return;
      }
      unawaited(_connectLiveKit(map));
      return;
    }

    // Флаг e2ee без ключа — только индикация (ключ приходит в call.token).
    if (type == 'call.started' ||
        type == 'call.ring' ||
        type == 'started' ||
        type == 'ring') {
      if (_session != null && parseCallE2eeFlag(map)) {
        _session = _session!.copyWith(e2eeEnabled: true);
        notifyListeners();
      }
      return;
    }

    if (type == 'call.accept' ||
        type == 'accept' ||
        type == 'call.accepted' ||
        type == 'accepted') {
      if (_session != null) _markRemoteAccepted();
      return;
    }

    if (type == 'error') {
      final payload = map['payload'];
      final code = payload is Map ? payload['code']?.toString() : null;
      final message = payload is Map ? payload['message']?.toString() : null;
      if (_session != null &&
          (code == 'not_found' ||
              code == 'invalid_state' ||
              code == 'forbidden')) {
        ApiLogger.instance.logEvent(
          'CALL',
          'signaling error during call: $code $message',
        );
        _session = _session!.copyWith(
          state: CallState.failed,
          error: message ?? code ?? 'error',
        );
        notifyListeners();
      }
      return;
    }

    // Собеседник сбросил / отменил / занят — закрыть UI (в т.ч. до соединения).
    if (type == 'reject' ||
        type == 'rejected' ||
        type == 'cancel' ||
        type == 'cancelled' ||
        type == 'canceled' ||
        type == 'hangup' ||
        type == 'ended' ||
        type == 'busy' ||
        type == 'call.reject' ||
        type == 'call.rejected' ||
        type == 'call.cancel' ||
        type == 'call.cancelled' ||
        type == 'call.canceled' ||
        type == 'call.hangup' ||
        type == 'call.ended' ||
        type == 'call.busy') {
      final callId = _extractCallId(map);
      final isCancel = type.contains('cancel');
      final isReject = type.contains('reject');
      final isBusy = type.contains('busy');

      if (_incomingMatchesEnd(callId, map)) {
        final invite = _incoming!;
        // Входящий ещё не принят: cancel инициатором → cancelled; иначе missed.
        final endedByCaller = isCancel ||
            type.contains('hangup') ||
            type.contains('ended');
        _emitCallChatResult(
          CallChatResult(
            dlgId: invite.dlgId ?? invite.groupId,
            callId: invite.callId,
            media: invite.video ? 'video' : 'audio',
            type: endedByCaller ? 'cancelled' : 'missed',
            rejectUsrId: endedByCaller ? invite.callerId : '',
            callerId: invite.callerId,
            callerName: invite.callerName,
            outgoing: false,
            peerUserId: invite.callerId,
          ),
        );
        _incoming = null;
        notifyListeners();
      }
      if (_session != null &&
          (callId == null ||
              callId == _session!.callId ||
              _session!.callId == 'pending')) {
        final session = _session!;
        _emitCallChatResult(
          _resultForRemoteEnd(
            session,
            cancelledByPeer: isCancel || isReject || isBusy,
            rejectedByCallee: isReject || isBusy,
          ),
        );
        _endRequested = false;
        _deferredEnd = null;
        _localEnding = false;
        unawaited(hangup(local: false));
      }
      return;
    }

    if (type == 'recording' || type == 'call.recording') {
      final payload = map['payload'];
      final active = map['active'] == true ||
          map['recording'] == true ||
          (payload is Map &&
              (payload['active'] == true || payload['recording'] == true));
      if (_session != null) {
        _session = _session!.copyWith(recording: active);
        notifyListeners();
      }
      return;
    }

    if (type == 'participant_joined' ||
        type == 'call.participant_joined') {
      if (_session != null) _markRemoteAccepted();
      notifyListeners();
      return;
    }
    if (type == 'participant_left' ||
        type == 'call.participant_left') {
      notifyListeners();
    }
  }

  String? _extractCallId(Map<String, dynamic> map) {
    final payload = map['payload'];
    final id = (map['callId'] ??
            map['call_id'] ??
            (payload is Map
                ? (payload['callId'] ?? payload['call_id'])
                : null))
        ?.toString()
        .trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// Returns true if deferred hangup was flushed (caller should stop handling).
  bool _maybeBindCallId(Map<String, dynamic> map) {
    final callId = _extractCallId(map);
    if (callId == null) return false;

    // Session уже очищена после локальной отмены — всё равно дослать cancel.
    if (_session == null) {
      if (_endRequested) {
        _flushDeferredEndIfNeeded(callId);
        return true;
      }
      return false;
    }

    final session = _session!;
    if (session.callId == 'pending' || session.callId.isEmpty) {
      _session = session.copyWith(callId: callId);
      notifyListeners();
      ApiLogger.instance.logEvent('CALL', 'bound callId $callId');
    }

    if (_endRequested) {
      final id = (_session?.callId != null &&
              _session!.callId.isNotEmpty &&
              _session!.callId != 'pending')
          ? _session!.callId
          : callId;
      _flushDeferredEndIfNeeded(id);
      unawaited(hangup(local: false));
      return true;
    }
    return false;
  }

  bool _incomingMatchesEnd(String? callId, Map<String, dynamic> map) {
    final inv = _incoming;
    if (inv == null) return false;
    if (callId == null || callId.isEmpty) return true;
    if (callId == inv.callId) return true;
    final payload = map['payload'];
    final dlg = (map['dlgId'] ??
            map['dlg_id'] ??
            (payload is Map
                ? (payload['dlgId'] ?? payload['dlg_id'])
                : null))
        ?.toString()
        .trim();
    if (dlg != null && dlg.isNotEmpty) {
      final invDlg = (inv.dlgId ?? inv.groupId)?.trim();
      if (invDlg != null && invDlg.isNotEmpty && invDlg == dlg) return true;
    }
    return false;
  }

  void _presentIncoming(IncomingCallInvite invite) {
    if (_incoming?.callId == invite.callId) return;
    if (hasActiveCall && _session?.callId != invite.callId) {
      _signaling.sendReject(
        callId: invite.callId,
        dlgId: invite.dlgId ?? invite.groupId,
      );
      return;
    }
    _incoming = invite;
    notifyListeners();
  }

  Future<void> _connectLiveKit(Map<String, dynamic> map) async {
    final payload = map['payload'];
    final body = payload is Map
        ? Map<String, dynamic>.from(payload)
        : map;

    final url = (body['url'] ??
            body['livekit_url'] ??
            body['ws_url'] ??
            body['server'] ??
            map['url'])
        ?.toString()
        .trim();
    final token = (body['token'] ??
            body['livekit_token'] ??
            body['access_token'] ??
            map['token'])
        ?.toString()
        .trim();
    final roomName =
        (body['room'] ?? body['room_name'] ?? map['room'])?.toString();
    final callId = (map['callId'] ??
            map['call_id'] ??
            body['callId'] ??
            body['call_id'] ??
            _session?.callId)
        ?.toString();

    if (url == null ||
        url.isEmpty ||
        token == null ||
        token.isEmpty ||
        _session == null) {
      ApiLogger.instance.logEvent('CALL', 'call.token incomplete');
      return;
    }

    if (_endRequested) {
      _flushDeferredEndIfNeeded(callId);
      return;
    }

    // Сервер выдаёт callId — привязываем к исходящему pending.
    if (callId != null &&
        callId.isNotEmpty &&
        (_session!.callId == 'pending' || _session!.callId == callId)) {
      _session = _session!.copyWith(callId: callId);
    } else if (callId != null &&
        callId.isNotEmpty &&
        callId != _session!.callId) {
      return;
    }

    final media = body['media']?.toString();
    if (media == 'video') {
      _camEnabled = true;
      _session = _session!.copyWith(mediaType: CallMediaType.video);
    }

    final e2ee = parseCallE2eeFlag(map) || (_session?.e2eeEnabled ?? false);
    final e2eeKey = parseCallE2eeKey(map);

    _session = _session!.copyWith(
      state: CallState.connectingMedia,
      livekitUrl: url,
      livekitToken: token,
      livekitRoom: roomName,
      e2eeEnabled: e2ee && e2eeKey != null,
    );
    notifyListeners();

    try {
      await _leaveRoom(keepSession: true);
      if (_endRequested || _session == null) {
        _flushDeferredEndIfNeeded(callId);
        return;
      }

      E2EEOptions? e2eeOptions;
      if (e2ee && e2eeKey != null) {
        // Shared-key frame encryption (без data-channel), как iOS CallManager.joinRoom.
        final keyProvider = await BaseKeyProvider.create(sharedKey: true);
        await keyProvider.setSharedKey(e2eeKey);
        e2eeOptions = E2EEOptions(keyProvider: keyProvider);
        ApiLogger.instance.logEvent('CALL', 'E2EE enabled for call');
      }

      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          e2eeOptions: e2eeOptions,
          defaultAudioPublishOptions: const AudioPublishOptions(
            name: 'microphone',
          ),
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            maxFrameRate: 30,
          ),
        ),
      );
      _room = room;
      _roomListener = room.createListener();
      _roomListener!
        ..on<RoomConnectedEvent>((_) {
          if (_endRequested || _session == null) return;
          // Подключение к комнате ≠ ответ собеседника (caller получает token сразу).
          if (_remoteAccepted ||
              _session!.direction == CallDirection.incoming) {
            _connectedAt ??= DateTime.now();
            _session = _session?.copyWith(state: CallState.active);
          } else if (_session!.state == CallState.ringing) {
            _session =
                _session?.copyWith(state: CallState.connectingMedia);
          }
          notifyListeners();
        })
        ..on<RoomDisconnectedEvent>((_) {
          if (_localEnding || _endRequested || _chatResultSent) {
            unawaited(hangup(local: false));
            return;
          }
          final session = _session;
          if (session != null) {
            _emitCallChatResult(
              _resultForRemoteEnd(session, cancelledByPeer: false),
            );
          }
          unawaited(hangup(local: false));
        })
        ..on<ParticipantConnectedEvent>((_) {
          _markRemoteAccepted();
          notifyListeners();
        })
        ..on<ParticipantDisconnectedEvent>((_) => notifyListeners())
        ..on<TrackSubscribedEvent>((_) => notifyListeners())
        ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
        ..on<LocalTrackPublishedEvent>((_) => notifyListeners());

      await room.connect(url, token);

      if (_endRequested || _session == null) {
        await _leaveRoom();
        _flushDeferredEndIfNeeded(callId);
        return;
      }

      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);
      if (_camEnabled) {
        await room.localParticipant?.setCameraEnabled(true);
      }

      // Remote уже в комнате (accept раньше connect).
      if (room.remoteParticipants.isNotEmpty) {
        _markRemoteAccepted();
      } else if (_session?.direction == CallDirection.incoming) {
        _connectedAt ??= DateTime.now();
        _session = _session?.copyWith(state: CallState.active);
        notifyListeners();
      } else {
        // Исходящий: ждём remote — UI остаётся «звоним…».
        if (_session?.state == CallState.ringing) {
          _session =
              _session?.copyWith(state: CallState.connectingMedia);
        }
        notifyListeners();
      }
    } catch (e, st) {
      if (_endRequested || _session == null) {
        _flushDeferredEndIfNeeded(callId);
        return;
      }
      ApiLogger.instance.logEvent('CALL', 'LiveKit connect failed: $e\n$st');
      _session = _session?.copyWith(
        state: CallState.failed,
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  void _emitCallChatResult(CallChatResult result) {
    if (_chatResultSent) return;
    final dlg = (result.dlgId ?? '').trim();
    final peer = result.peerUserId.trim();
    // dlgId может быть пуст — AppState найдёт диалог по peerUserId.
    if ((dlg.isEmpty || dlg == '0') && peer.isEmpty) {
      ApiLogger.instance.logEvent(
        'CALL',
        'chat result skipped: no dlg/peer callId=${result.callId}',
      );
      return;
    }
    _chatResultSent = true;
    try {
      onCallChatResult?.call(result);
    } catch (e) {
      ApiLogger.instance.logEvent('CALL', 'onCallChatResult failed: $e');
    }
  }

  CallChatResult _resultForLocalHangup(CallSession session) {
    final me = _localUserId ?? '';
    final answered = _isAnswered(session);
    final media = session.mediaType == CallMediaType.video ? 'video' : 'audio';
    final peerUserId =
        session.peers.isNotEmpty ? session.peers.first.userId : '';
    final callerId = session.direction == CallDirection.outgoing
        ? me
        : peerUserId;
    final callerName = session.direction == CallDirection.outgoing
        ? (_localUserName ?? '')
        : (session.peers.isNotEmpty ? session.peers.first.name : session.title);
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;
    // groupId часто = dlgId для 1:1 invite — используем как fallback.
    final dlgId = session.dlgId ?? session.groupId;

    if (answered) {
      return CallChatResult(
        dlgId: dlgId,
        callId: session.callId,
        media: media,
        type: 'talk',
        durationSec: duration > 0 ? duration : 0,
        callerId: callerId,
        callerName: callerName,
        outgoing: session.direction == CallDirection.outgoing,
        peerUserId: peerUserId,
      );
    }

    if (session.direction == CallDirection.outgoing) {
      return CallChatResult(
        dlgId: dlgId,
        callId: session.callId == 'pending' ? '' : session.callId,
        media: media,
        type: 'cancelled',
        rejectUsrId: me,
        callerId: callerId.isNotEmpty ? callerId : me,
        callerName: callerName,
        outgoing: true,
        peerUserId: peerUserId,
      );
    }
    return CallChatResult(
      dlgId: dlgId,
      callId: session.callId == 'pending' ? '' : session.callId,
      media: media,
      type: 'missed',
      callerId: callerId,
      callerName: callerName,
      outgoing: false,
      peerUserId: peerUserId,
    );
  }

  CallChatResult _resultForRemoteEnd(
    CallSession session, {
    required bool cancelledByPeer,
    bool rejectedByCallee = false,
  }) {
    final me = _localUserId ?? '';
    final media = session.mediaType == CallMediaType.video ? 'video' : 'audio';
    final peerId =
        session.peers.isNotEmpty ? session.peers.first.userId : '';
    final peerName =
        session.peers.isNotEmpty ? session.peers.first.name : session.title;
    final callerId = session.direction == CallDirection.outgoing ? me : peerId;
    final callerName = session.direction == CallDirection.outgoing
        ? (_localUserName ?? '')
        : peerName;
    final answered = _isAnswered(session);
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;
    final dlgId = session.dlgId ?? session.groupId;
    final safeCallId =
        session.callId == 'pending' ? '' : session.callId;

    if (answered) {
      return CallChatResult(
        dlgId: dlgId,
        callId: safeCallId,
        media: media,
        type: 'talk',
        durationSec: duration > 0 ? duration : 0,
        callerId: callerId,
        callerName: callerName,
        outgoing: session.direction == CallDirection.outgoing,
        peerUserId: peerId,
      );
    }

    if (cancelledByPeer) {
      final rejectId = rejectedByCallee
          ? (session.direction == CallDirection.outgoing ? peerId : me)
          : callerId;
      return CallChatResult(
        dlgId: dlgId,
        callId: safeCallId,
        media: media,
        type: 'cancelled',
        rejectUsrId: rejectId,
        callerId: callerId,
        callerName: callerName,
        outgoing: session.direction == CallDirection.outgoing,
        peerUserId: peerId,
      );
    }

    return CallChatResult(
      dlgId: dlgId,
      callId: safeCallId,
      media: media,
      type: 'missed',
      callerId: callerId,
      callerName: callerName,
      outgoing: session.direction == CallDirection.outgoing,
      peerUserId: peerId,
    );
  }

  Future<void> _leaveRoom({bool keepSession = false}) async {
    try {
      await _roomListener?.dispose();
    } catch (_) {}
    _roomListener = null;
    try {
      await _room?.disconnect();
      await _room?.dispose();
    } catch (_) {}
    _room = null;
    if (!keepSession) {
      // no-op
    }
  }

  @override
  void dispose() {
    unawaited(shutdown());
    _signaling.dispose();
    super.dispose();
  }
}

class _DeferredCallEnd {
  final bool preferCancel;
  final List<String> peers;
  final String? dlgId;
  final String? callId;

  const _DeferredCallEnd({
    required this.preferCancel,
    required this.peers,
    this.dlgId,
    this.callId,
  });

  _DeferredCallEnd copyWith({
    bool? preferCancel,
    List<String>? peers,
    String? dlgId,
    String? callId,
  }) {
    return _DeferredCallEnd(
      preferCancel: preferCancel ?? this.preferCancel,
      peers: peers ?? this.peers,
      dlgId: dlgId ?? this.dlgId,
      callId: callId ?? this.callId,
    );
  }
}
