import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../models/message_view_model.dart';
import 'media_file_loader.dart';
import 'media_file_url.dart';

/// Состояние текущего голосового (один поток на приложение).
class VoicePlaybackState {
  final String? messageId;
  final bool playing;
  final bool loading;
  final double progress; // 0…1
  final Duration position;
  final Duration duration;
  final double speed;

  const VoicePlaybackState({
    this.messageId,
    this.playing = false,
    this.loading = false,
    this.progress = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
  });

  static const empty = VoicePlaybackState();

  VoicePlaybackState copyWith({
    String? messageId,
    bool clearMessageId = false,
    bool? playing,
    bool? loading,
    double? progress,
    Duration? position,
    Duration? duration,
    double? speed,
  }) {
    return VoicePlaybackState(
      messageId: clearMessageId ? null : (messageId ?? this.messageId),
      playing: playing ?? this.playing,
      loading: loading ?? this.loading,
      progress: progress ?? this.progress,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
    );
  }
}

/// Воспроизведение голосовых (m4a/mp3) через just_audio —
/// как Forum_ios `AVPlayer` для audio-only (video_player их часто не играет).
class VoicePlayer {
  VoicePlayer._();

  static final state = ValueNotifier<VoicePlaybackState>(VoicePlaybackState.empty);

  /// Совместимость со старыми слушателями.
  static final playingMessageId = ValueNotifier<String?>(null);

  static AudioPlayer? _player;
  static StreamSubscription<Duration>? _positionSub;
  static StreamSubscription<PlayerState>? _playerStateSub;
  static StreamSubscription<void>? _completedSub;
  static String? _currentId;
  static double _speed = 1;

  static bool isPlaying(String messageId) {
    final s = state.value;
    return s.messageId == messageId && s.playing;
  }

  static bool isCurrent(String messageId) => state.value.messageId == messageId;

  static Future<void> toggle(
    MessageViewModel message, {
    double? speed,
  }) async {
    final id = _playbackId(message);
    if (id.isEmpty) return;

    if (speed != null && speed > 0) {
      _speed = speed;
    }

    final player = _player;
    // Своё состояние надёжнее player.playing (на desktop иногда врёт).
    final isCurrent = _currentId == id && player != null;
    if (isCurrent) {
      if (state.value.playing) {
        await player.pause();
        _emit(messageId: id, playing: false);
      } else {
        await player.setSpeed(_speed);
        await player.play();
        _emit(messageId: id, playing: true, speed: _speed);
      }
      return;
    }

    await _start(message, speed: _speed);
  }

  static String _playbackId(MessageViewModel message) {
    final id = message.id.trim();
    if (id.isNotEmpty) return id;
    final hash = message.hash.trim();
    if (hash.isNotEmpty) return hash;
    return '';
  }

  static Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 3.0);
    final player = _player;
    if (player != null) {
      await player.setSpeed(_speed);
    }
    _emit(speed: _speed);
  }

  static Future<void> _start(
    MessageViewModel message, {
    required double speed,
  }) async {
    final id = _playbackId(message);
    if (id.isEmpty) {
      throw StateError('Нет id голосового сообщения');
    }
    await stop();

    final file = _voiceFile(message);
    if (file == null) {
      throw StateError('Нет файла голосового сообщения');
    }

    _currentId = id;
    _speed = speed;
    _emit(
      messageId: id,
      playing: false,
      loading: true,
      progress: 0,
      position: Duration.zero,
      duration: Duration.zero,
      speed: speed,
    );
    playingMessageId.value = id;

    try {
      final localPath = await MediaFileLoader.ensureCached(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
      final local = File(localPath);
      if (!await local.exists() || await local.length() <= 0) {
        throw StateError('Пустой аудиофайл');
      }

      final player = AudioPlayer();
      _player = player;

      final duration = await player.setFilePath(localPath);
      await player.setSpeed(speed);

      _positionSub = player.positionStream.listen(_onPosition);
      _playerStateSub = player.playerStateStream.listen(_onPlayerState);
      _completedSub = player.processingStateStream.listen((ps) {
        if (ps == ProcessingState.completed) {
          unawaited(stop());
        }
      });

      await player.play();

      _emit(
        messageId: id,
        playing: true,
        loading: false,
        progress: 0,
        position: Duration.zero,
        duration: duration ?? Duration(seconds: file.duration),
        speed: speed,
      );
    } catch (e) {
      await stop();
      rethrow;
    }
  }

  static void _onPosition(Duration pos) {
    final player = _player;
    if (player == null) return;
    final total = player.duration ?? state.value.duration;
    var progress = 0.0;
    if (total.inMilliseconds > 0) {
      progress = (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    }
    _emit(
      messageId: _currentId,
      playing: player.playing,
      loading: false,
      progress: progress,
      position: pos,
      duration: total,
      speed: _speed,
    );
  }

  static void _onPlayerState(PlayerState ps) {
    _emit(
      messageId: _currentId,
      playing: ps.playing,
      loading: false,
      speed: _speed,
    );
  }

  static void _emit({
    String? messageId,
    bool? playing,
    bool? loading,
    double? progress,
    Duration? position,
    Duration? duration,
    double? speed,
  }) {
    final next = state.value.copyWith(
      messageId: messageId,
      playing: playing,
      loading: loading,
      progress: progress,
      position: position,
      duration: duration,
      speed: speed,
    );
    state.value = next;
    // Держим id пока сообщение «текущее» (в т.ч. на паузе), чтобы UI не терял контекст.
    playingMessageId.value = next.messageId;
  }

  static MediaFile? _voiceFile(MessageViewModel message) {
    if (message.files.isEmpty) return null;
    final raw = message.files.first;
    var kind = raw.kind.trim().toLowerCase();
    if (kind.isEmpty || kind == 'voice') {
      final ext = raw.fname.contains('.')
          ? raw.fname.split('.').last.toLowerCase()
          : '';
      kind = ext.isNotEmpty ? ext : 'm4a';
    }
    final file = MediaFile(
      hash: raw.hash,
      url: raw.url,
      fname: raw.fname,
      fdir: raw.fdir,
      kind: kind,
      title: raw.title,
      size: raw.size,
      duration: raw.duration,
      URL: raw.URL,
      bytes: raw.bytes,
    );
    if (file.url.trim().isEmpty) {
      file.url = MediaFileUrl.resolve(file);
    }
    if (file.url.isNotEmpty) {
      file.url = ApiConfig.rewriteLegacyHost(file.url);
    }
    return file;
  }

  static Future<void> stop() async {
    final player = _player;
    _player = null;
    _currentId = null;

    await _positionSub?.cancel();
    await _playerStateSub?.cancel();
    await _completedSub?.cancel();
    _positionSub = null;
    _playerStateSub = null;
    _completedSub = null;

    state.value = VoicePlaybackState.empty.copyWith(speed: _speed);
    playingMessageId.value = null;

    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
