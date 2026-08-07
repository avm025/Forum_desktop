import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../calls/call_manager.dart';
import '../../calls/call_models.dart';
import '../../theme/app_theme.dart';
import 'call_controls.dart';
import 'call_e2ee_badge.dart';

/// Экран 1:1 аудиозвонка.
class AudioCallScreen extends StatelessWidget {
  const AudioCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallManager>();
    final session = calls.session;
    final p = context.palette;
    if (session == null) return const SizedBox.shrink();

    final peer = session.peers.isNotEmpty ? session.peers.first : null;
    final status = _statusLabel(session.state);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1E),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              peer?.name.isNotEmpty == true ? peer!.name : session.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(color: p.lime, fontSize: 15),
            ),
            const CallE2eeBadge(),
            const Spacer(),
            CircleAvatar(
              radius: 64,
              backgroundColor: p.purple.withValues(alpha: 0.35),
              backgroundImage: peer?.avatarUrl.isNotEmpty == true
                  ? NetworkImage(peer!.avatarUrl)
                  : null,
              child: peer?.avatarUrl.isNotEmpty == true
                  ? null
                  : Text(
                      _initials(peer?.name ?? session.title),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const Spacer(),
            CallControlsBar(
              micOn: calls.micEnabled,
              camOn: calls.camEnabled,
              speakerOn: calls.speakerOn,
              showCamera: true,
              showSwitchCamera: false,
              showRecord: false,
              showInvite: calls.canInviteParticipants,
              onToggleMic: calls.toggleMute,
              onToggleCam: calls.toggleVideo,
              onToggleSpeaker: calls.toggleSpeaker,
              onInvite: calls.openInvitePicker,
              onHangup: () => calls.hangup(),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(CallState state) {
    return switch (state) {
      CallState.ringing => 'Вызов…',
      CallState.connecting || CallState.connectingMedia => 'Соединение…',
      CallState.active => 'Идёт разговор',
      CallState.failed => 'Ошибка соединения',
      CallState.ended => 'Завершён',
      CallState.idle => '',
    };
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts[0].characters.first}${parts[1].characters.first}'
        .toUpperCase();
  }
}

/// Экран 1:1 видеозвонка.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();

  static VideoTrack? _firstRemoteVideo(Room? room) {
    if (room == null) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track != null && pub.subscribed) return track;
      }
    }
    return null;
  }

  static VideoTrack? _localVideo(Room? room) {
    final pubs = room?.localParticipant?.videoTrackPublications;
    if (pubs == null) return null;
    for (final pub in pubs) {
      final track = pub.track;
      if (track != null) return track;
    }
    return null;
  }

  static String _statusLabel(CallState state) {
    return switch (state) {
      CallState.ringing => 'Вызов…',
      CallState.connecting || CallState.connectingMedia => 'Соединение…',
      CallState.active => '',
      CallState.failed => 'Ошибка соединения',
      _ => '',
    };
  }
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  /// Как в Telegram: по умолчанию удалённое — на весь экран, своё — PiP.
  bool _localIsPip = true;

  static const _pipWidth = 120.0;
  static const _pipHeight = 180.0; // всегда вертикальный кадр 2:3

  void _swapViews() {
    setState(() => _localIsPip = !_localIsPip);
  }

  Widget _videoPane({
    required VideoTrack track,
    required bool isLocal,
    required Key key,
  }) {
    // Окна (main / вертикальный PiP) не меняют форму — меняется только трек.
    // cover = как в Telegram: кадр заполняет слот с обрезкой, без «переворота».
    return KeyedSubtree(
      key: key,
      child: VideoTrackRenderer(
        track,
        fit: VideoViewFit.cover,
        mirrorMode:
            isLocal ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
        autoCenter: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallManager>();
    final session = calls.session;
    final room = calls.room;
    if (session == null) return const SizedBox.shrink();

    final remote = VideoCallScreen._firstRemoteVideo(room);
    final local = VideoCallScreen._localVideo(room);
    final canSwap = remote != null && local != null;

    final VideoTrack? mainTrack;
    final VideoTrack? pipTrack;
    final bool mainIsLocal;
    if (!canSwap) {
      mainTrack = remote ?? local;
      pipTrack = null;
      mainIsLocal = remote == null && local != null;
    } else if (_localIsPip) {
      mainTrack = remote;
      pipTrack = local;
      mainIsLocal = false;
    } else {
      mainTrack = local;
      pipTrack = remote;
      mainIsLocal = true;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canSwap ? _swapViews : null,
              child: mainTrack != null
                  ? _videoPane(
                      track: mainTrack,
                      isLocal: mainIsLocal,
                      key: ValueKey('main-${mainTrack.hashCode}'),
                    )
                  : Container(
                      color: const Color(0xFF1A1A1E),
                      alignment: Alignment.center,
                      child: Text(
                        VideoCallScreen._statusLabel(session.state),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
            ),
          ),
          if (pipTrack != null)
            Positioned(
              right: 16,
              top: 56,
              width: _pipWidth,
              height: _pipHeight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canSwap ? _swapViews : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _videoPane(
                        track: pipTrack,
                        isLocal: !mainIsLocal,
                        key: ValueKey('pip-${pipTrack.hashCode}'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 48,
            child: Column(
              children: [
                if (VideoCallScreen._statusLabel(session.state).isNotEmpty)
                  Text(
                    VideoCallScreen._statusLabel(session.state),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                const CallE2eeBadge(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: CallControlsBar(
              micOn: calls.micEnabled,
              camOn: calls.camEnabled,
              speakerOn: calls.speakerOn,
              showCamera: true,
              showSwitchCamera: true,
              showRecord: false,
              showInvite: calls.canInviteParticipants,
              onToggleMic: calls.toggleMute,
              onToggleCam: calls.toggleVideo,
              onToggleSpeaker: calls.toggleSpeaker,
              onSwitchCamera: calls.switchCamera,
              onInvite: calls.openInvitePicker,
              onHangup: () => calls.hangup(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Групповой звонок — сетка участников.
class GroupCallScreen extends StatelessWidget {
  const GroupCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallManager>();
    final session = calls.session;
    final room = calls.room;
    if (session == null) return const SizedBox.shrink();

    final tiles = <_Tile>[];
    final localVideo = VideoCallScreen._localVideo(room);
    tiles.add(_Tile(
      name: 'Вы',
      video: localVideo,
      muted: !calls.micEnabled,
    ));
    if (room != null) {
      for (final participant in room.remoteParticipants.values) {
        VideoTrack? video;
        for (final pub in participant.videoTrackPublications) {
          if (pub.track != null && pub.subscribed) {
            video = pub.track;
            break;
          }
        }
        tiles.add(_Tile(
          name: participant.name.isNotEmpty
              ? participant.name
              : participant.identity,
          video: video,
          muted: participant.isMuted,
        ));
      }
    } else {
      for (final peer in session.peers) {
        tiles.add(_Tile(name: peer.name, video: null, muted: false));
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title.isNotEmpty ? session.title : 'Групповой звонок',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (session.recording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const CallE2eeBadge(compact: true),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3 / 4,
                ),
                itemCount: tiles.length,
                itemBuilder: (context, i) {
                  final tile = tiles[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: const Color(0xFF2A2A30),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (tile.video != null)
                            VideoTrackRenderer(
                              tile.video!,
                              mirrorMode: i == 0
                                  ? VideoViewMirrorMode.mirror
                                  : VideoViewMirrorMode.auto,
                            )
                          else
                            Center(
                              child: Text(
                                AudioCallScreen._initials(tile.name),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Positioned(
                            left: 8,
                            bottom: 8,
                            right: 8,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tile.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (tile.muted)
                                  const Icon(
                                    Icons.mic_off,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            CallControlsBar(
              micOn: calls.micEnabled,
              camOn: calls.camEnabled,
              speakerOn: calls.speakerOn,
              showCamera: true,
              showSwitchCamera: true,
              showRecord: true,
              showInvite: calls.canInviteParticipants,
              recording: session.recording,
              onToggleMic: calls.toggleMute,
              onToggleCam: calls.toggleVideo,
              onToggleSpeaker: calls.toggleSpeaker,
              onSwitchCamera: calls.switchCamera,
              onToggleRecord: calls.toggleRecording,
              onInvite: calls.openInvitePicker,
              onHangup: () => calls.hangup(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Tile {
  final String name;
  final VideoTrack? video;
  final bool muted;
  const _Tile({required this.name, required this.video, required this.muted});
}
