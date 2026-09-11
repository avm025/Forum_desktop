import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../utils/media_display_name.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';

/// Воспроизведение видео из чата.
class FullscreenVideoViewer extends StatefulWidget {
  final MediaFile file;

  const FullscreenVideoViewer({super.key, required this.file});

  static Future<void> show(BuildContext context, MediaFile file) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => FullscreenVideoViewer(file: file),
    );
  }

  @override
  State<FullscreenVideoViewer> createState() => _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends State<FullscreenVideoViewer> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final downloadUrl = MediaFileUrl.resolve(widget.file);
      final localPath = await MediaFileLoader.ensureCached(
        widget.file,
        downloadUrl: downloadUrl,
      );
      final file = File(localPath);
      if (!await file.exists() || await file.length() <= 0) {
        throw StateError('Локальный файл пуст');
      }

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = MediaDisplayName.forFile(widget.file);

    return Dialog(
      backgroundColor: Colors.black87,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 32,
          maxHeight: MediaQuery.sizeOf(context).height - 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, title),
            Flexible(
              child: Center(
                child: _body(),
              ),
            ),
            if (_controller != null && _controller!.value.isInitialized)
              _controls(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final thumb = MediaThumbCache.peekSync(widget.file);
    if (_loading) {
      if (thumb != null) {
        return Image.file(
          thumb,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      }
      return const SizedBox.shrink();
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Не удалось загрузить видео\n$_error',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final c = _controller!;
    final ratio = c.value.aspectRatio == 0 ? (16 / 9) : c.value.aspectRatio;
    return AspectRatio(
      aspectRatio: ratio,
      child: VideoPlayer(c),
    );
  }

  Widget _controls() {
    final c = _controller!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              c.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                c.value.isPlaying ? c.pause() : c.play();
              });
            },
          ),
          Expanded(
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
