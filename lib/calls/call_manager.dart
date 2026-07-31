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
  String? _localUserId;

  CallSession? get session => _session;
  IncomingCallInvite? get incoming => _incoming;
  Room? get room => _room;
  bool get micEnabled => _micEnabled;
  bool get camEnabled => _camEnabled;
  bool get speakerOn => _speakerOn;
  bool get invitePickerOpen => _invitePickerOpen;
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
    );
    notifyListeners();
    _signaling.sendAccept(callId: invite.callId, video: _camEnabled);
  }

  void declineIncoming() {
    final invite = _incoming;
    if (invite == null) return;
    _signaling.sendReject(callId: invite.callId);
    _incoming = null;
    notifyListeners();
  }

  Future<void> hangup({bool local = true}) async {
    final session = _session;
    _invitePickerOpen = false;
    if (session != null && local) {
      final peers = session.peers
          .map((p) => p.userId.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (session.callId.isEmpty || session.callId == 'pending') {
        // Пока нет callId — шлём hangup по callees/dlgId и ждём call.token для точного id.
        _endRequested = true;
        _signaling.sendHangup(
          callId: 'pending',
          callees: peers,
          dlgId: session.dlgId ?? session.groupId,
        );
        ApiLogger.instance.logEvent(
          'CALL',
          'hangup before callId — sent by callees, defer by id',
        );
      } else {
        _endRequested = false;
        _signaling.sendHangup(
          callId: session.callId,
          callees: peers,
          dlgId: session.dlgId ?? session.groupId,
        );
      }
    } else {
      _endRequested = false;
    }
    await _leaveRoom();
    if (_session != null) {
      _session = _session!.copyWith(state: CallState.ended);
      notifyListeners();
      _session = null;
      notifyListeners();
    }
  }

  void _hangupCallOnServer(String callId) {
    if (callId.isEmpty || callId == 'pending') return;
    _signaling.sendHangup(callId: callId);
    ApiLogger.instance.logEvent('CALL', 'deferred hangup $callId');
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
        final callId = _extractCallId(map);
        if (callId != null) _hangupCallOnServer(callId);
        _endRequested = false;
        return;
      }
      unawaited(_connectLiveKit(map));
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
      if (_incoming != null &&
          (callId == null || callId == _incoming!.callId)) {
        _incoming = null;
        notifyListeners();
      }
      if (_session != null &&
          (callId == null ||
              callId == _session!.callId ||
              _session!.callId == 'pending')) {
        _endRequested = false;
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
        type == 'participant_left' ||
        type == 'call.participant_joined' ||
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
    final session = _session;
    if (session == null) return false;

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
      _hangupCallOnServer(id);
      _endRequested = false;
      unawaited(hangup(local: false));
      return true;
    }
    return false;
  }

  void _presentIncoming(IncomingCallInvite invite) {
    if (_incoming?.callId == invite.callId) return;
    if (hasActiveCall && _session?.callId != invite.callId) {
      _signaling.sendReject(callId: invite.callId);
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
      if (callId != null && callId.isNotEmpty) {
        _hangupCallOnServer(callId);
      }
      _endRequested = false;
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

    _session = _session!.copyWith(
      state: CallState.connectingMedia,
      livekitUrl: url,
      livekitToken: token,
      livekitRoom: roomName,
    );
    notifyListeners();

    try {
      await _leaveRoom(keepSession: true);
      if (_endRequested || _session == null) {
        if (callId != null && callId.isNotEmpty) {
          _hangupCallOnServer(callId);
        }
        _endRequested = false;
        return;
      }
      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            name: 'microphone',
          ),
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 30,
          ),
        ),
      );
      _room = room;
      _roomListener = room.createListener();
      _roomListener!
        ..on<RoomConnectedEvent>((_) {
          if (_endRequested || _session == null) return;
          _session = _session?.copyWith(state: CallState.active);
          notifyListeners();
        })
        ..on<RoomDisconnectedEvent>((_) {
          unawaited(hangup(local: false));
        })
        ..on<ParticipantConnectedEvent>((_) => notifyListeners())
        ..on<ParticipantDisconnectedEvent>((_) => notifyListeners())
        ..on<TrackSubscribedEvent>((_) => notifyListeners())
        ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
        ..on<LocalTrackPublishedEvent>((_) => notifyListeners());

      await room.connect(url, token);

      if (_endRequested || _session == null) {
        await _leaveRoom();
        if (callId != null && callId.isNotEmpty) {
          _hangupCallOnServer(callId);
        }
        _endRequested = false;
        return;
      }

      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);
      if (_camEnabled) {
        await room.localParticipant?.setCameraEnabled(true);
      }

      _session = _session?.copyWith(state: CallState.active);
      notifyListeners();
    } catch (e, st) {
      if (_endRequested || _session == null) {
        _endRequested = false;
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
