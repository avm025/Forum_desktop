import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../models/message_view_model.dart';
import 'media_file_loader.dart';
import 'media_file_url.dart';

/// Воспроизведение голосовых (mp3/m4a) — один поток на всё приложение.
class VoicePlayer {
  VoicePlayer._();

  static final playingMessageId = ValueNotifier<String?>(null);
  static VideoPlayerController? _controller;
  static String? _currentId;

  static bool isPlaying(String messageId) =>
      _currentId == messageId && (_controller?.value.isPlaying ?? false);

  static Future<void> toggle(MessageViewModel message) async {
    final id = message.id.trim();
    if (id.isEmpty) return;

    if (_currentId == id && _controller != null) {
      if (_controller!.value.isPlaying) {
        await _controller!.pause();
        playingMessageId.value = null;
      } else {
        await _controller!.play();
        playingMessageId.value = id;
      }
      return;
    }

    await stop();
    final file = _voiceFile(message);
    if (file == null) return;

    try {
      final source = await MediaFileLoader.resolve(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );

      final VideoPlayerController controller;
      if (source.hasLocalPath) {
        controller = VideoPlayerController.file(File(source.localPath!));
      } else if (source.networkUrl.isNotEmpty) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(source.networkUrl),
          httpHeaders: ApiConfig.fileHeaders,
        );
      } else {
        return;
      }

      await controller.initialize();
      _controller = controller;
      _currentId = id;
      playingMessageId.value = id;

      controller.addListener(_onTick);
      await controller.play();
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  static void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final done = c.value.duration > Duration.zero &&
        c.value.position >= c.value.duration;
    if (done) {
      unawaited(stop());
    }
  }

  static MediaFile? _voiceFile(MessageViewModel message) {
    if (message.files.isEmpty) return null;
    final raw = message.files.first;
    final file = MediaFile(
      hash: raw.hash,
      url: raw.url,
      fname: raw.fname,
      fdir: raw.fdir,
      kind: raw.kind.isNotEmpty ? raw.kind : 'mp3',
      title: raw.title,
      size: raw.size,
      duration: raw.duration,
      URL: raw.URL,
      bytes: raw.bytes,
    );
    if (file.url.trim().isEmpty) {
      file.url = MediaFileUrl.resolve(file);
    }
    return file;
  }

  static Future<void> stop() async {
    final c = _controller;
    _controller = null;
    _currentId = null;
    playingMessageId.value = null;
    if (c != null) {
      c.removeListener(_onTick);
      await c.dispose();
    }
  }
}
