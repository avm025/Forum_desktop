import 'dart:convert';

// Модели звонков — порт Forum iOS CallModels.swift (controllers_map.md).

enum CallMediaType { audio, video }

enum CallDirection { outgoing, incoming }

enum CallState {
  idle,
  connecting,
  ringing,
  connectingMedia,
  active,
  ended,
  failed,
}

class CallParticipant {
  final String userId;
  final String name;
  final String avatarUrl;
  final String callIdentity;
  final bool isLocal;
  final bool audioMuted;
  final bool videoEnabled;

  const CallParticipant({
    required this.userId,
    this.name = '',
    this.avatarUrl = '',
    this.callIdentity = '',
    this.isLocal = false,
    this.audioMuted = false,
    this.videoEnabled = false,
  });

  CallParticipant copyWith({
    String? name,
    String? avatarUrl,
    String? callIdentity,
    bool? audioMuted,
    bool? videoEnabled,
  }) {
    return CallParticipant(
      userId: userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      callIdentity: callIdentity ?? this.callIdentity,
      isLocal: isLocal,
      audioMuted: audioMuted ?? this.audioMuted,
      videoEnabled: videoEnabled ?? this.videoEnabled,
    );
  }
}

class CallSession {
  final String callId;
  final CallDirection direction;
  final CallMediaType mediaType;
  final bool isGroup;
  final String? dlgId;
  final String? groupId;
  final String title;
  final List<CallParticipant> peers;
  final CallState state;
  final String? livekitUrl;
  final String? livekitToken;
  final String? livekitRoom;
  final bool recording;
  /// LiveKit frame E2EE (call_e2ee.md) — флаг с `call.token` / `call.ring` / `call.started`.
  final bool e2eeEnabled;
  final String? error;

  const CallSession({
    required this.callId,
    required this.direction,
    required this.mediaType,
    this.isGroup = false,
    this.dlgId,
    this.groupId,
    this.title = '',
    this.peers = const [],
    this.state = CallState.idle,
    this.livekitUrl,
    this.livekitToken,
    this.livekitRoom,
    this.recording = false,
    this.e2eeEnabled = false,
    this.error,
  });

  bool get wantsVideo => mediaType == CallMediaType.video;

  CallSession copyWith({
    String? callId,
    CallState? state,
    List<CallParticipant>? peers,
    String? livekitUrl,
    String? livekitToken,
    String? livekitRoom,
    bool? recording,
    bool? e2eeEnabled,
    String? error,
    String? title,
    CallMediaType? mediaType,
    bool? isGroup,
    String? groupId,
    String? dlgId,
  }) {
    return CallSession(
      callId: callId ?? this.callId,
      direction: direction,
      mediaType: mediaType ?? this.mediaType,
      isGroup: isGroup ?? this.isGroup,
      dlgId: dlgId ?? this.dlgId,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      peers: peers ?? this.peers,
      state: state ?? this.state,
      livekitUrl: livekitUrl ?? this.livekitUrl,
      livekitToken: livekitToken ?? this.livekitToken,
      livekitRoom: livekitRoom ?? this.livekitRoom,
      recording: recording ?? this.recording,
      e2eeEnabled: e2eeEnabled ?? this.e2eeEnabled,
      error: error,
    );
  }
}

/// Входящий invite до accept (UI + FCM).
class IncomingCallInvite {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerAvatar;
  final bool video;
  final bool isGroup;
  final String? groupId;
  final String? dlgId;
  final String title;
  final bool e2eeEnabled;

  const IncomingCallInvite({
    required this.callId,
    required this.callerId,
    this.callerName = '',
    this.callerAvatar = '',
    this.video = false,
    this.isGroup = false,
    this.groupId,
    this.dlgId,
    this.title = '',
    this.e2eeEnabled = false,
  });
}

/// Парсинг флага `e2ee` из WS payload (как `usr.e2e` на сервере).
bool parseCallE2eeFlag(Map<String, dynamic> map) {
  final payload = map['payload'];
  final body = payload is Map ? Map<String, dynamic>.from(payload) : map;
  return _truthy(body['e2ee'] ?? map['e2ee']);
}

String? parseCallE2eeKey(Map<String, dynamic> map) {
  final payload = map['payload'];
  final body = payload is Map ? Map<String, dynamic>.from(payload) : map;
  final key = (body['e2eeKey'] ??
          body['e2ee_key'] ??
          map['e2eeKey'] ??
          map['e2ee_key'])
      ?.toString()
      .trim();
  if (key == null || key.isEmpty) return null;
  return key;
}

bool _truthy(dynamic v) {
  if (v == true || v == 1) return true;
  final s = v?.toString().trim().toLowerCase() ?? '';
  return s == '1' ||
      s == 't' ||
      s == 'true' ||
      s == 'yes' ||
      s == 'y' ||
      s == 'on';
}

/// Результат звонка для пузыря `type=call` в чате (msg_call.md).
class CallChatResult {
  final String? dlgId;
  final String callId;
  final String media; // audio | video
  final String type; // missed | cancelled | talk
  final int durationSec;
  final String rejectUsrId;
  final String callerId;
  final String callerName;
  final bool outgoing;
  /// Собеседник 1:1 (для поиска диалога, если dlgId пуст).
  final String peerUserId;

  const CallChatResult({
    required this.dlgId,
    required this.callId,
    required this.media,
    required this.type,
    this.durationSec = 0,
    this.rejectUsrId = '',
    required this.callerId,
    this.callerName = '',
    required this.outgoing,
    this.peerUserId = '',
  });

  String get bodyJson {
    final id = callId.trim();
    final map = <String, dynamic>{
      'media': media,
      'type': type,
      if (id.isNotEmpty && id != 'pending') 'call_id': id,
      if (type == 'talk' && durationSec > 0) 'duration': durationSec,
      if (type == 'cancelled' && rejectUsrId.isNotEmpty)
        'reject_usr_id': rejectUsrId,
    };
    return jsonEncode(map);
  }
}

