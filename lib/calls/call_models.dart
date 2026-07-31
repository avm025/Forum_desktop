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
  });
}
