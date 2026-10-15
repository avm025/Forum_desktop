import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';

/// Кадр видео в пузыре через [VideoPlayer] (Windows и fallback без JPEG-превью).
class InlineVideoPreview extends StatefulWidget {
  final MediaFile file;
  final double width;
  final double height;
  final BoxFit fit;

  const InlineVideoPreview({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _InlineVideoPreviewState extends State<InlineVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant InlineVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.hash != widget.file.hash ||
        oldWidget.file.url != widget.file.url ||
        oldWidget.file.URL != widget.file.URL) {
      _start();
    }
  }

  @override
  void dispose() {
    _gen++;
    _disposeController();
    super.dispose();
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _start() async {
    final gen = ++_gen;
    await _disposeController();
    if (!mounted || gen != _gen) return;
    setState(() {
      _ready = false;
      _failed = false;
    });

    VideoPlayerController? controller;
    try {
      final local = widget.file.URL?.trim() ?? '';
      if (local.isNotEmpty &&
          !local.startsWith('http') &&
          File(local).existsSync()) {
        controller = VideoPlayerController.file(File(local));
      } else {
        final cached = await MediaFileLoader.cachedPathIfExists(widget.file);
        if (gen != _gen) return;
        if (cached != null) {
          controller = VideoPlayerController.file(File(cached));
        } else {
          final url = MediaFileUrl.resolve(widget.file);
          if (!url.startsWith('http')) {
            throw StateError('Нет URL видео');
          }
          controller = VideoPlayerController.networkUrl(
            Uri.parse(ApiConfig.rewriteLegacyHost(url)),
            httpHeaders: ApiConfig.fileHeaders,
          );
        }
      }

      await controller.initialize().timeout(const Duration(seconds: 15));
      if (gen != _gen || !mounted) {
        await controller.dispose();
        return;
      }
      if (!controller.value.isInitialized || controller.value.hasError) {
        await controller.dispose();
        throw StateError('init failed');
      }

      await controller.setVolume(0);
      final dur = controller.value.duration;
      if (dur > const Duration(milliseconds: 400)) {
        await controller.seekTo(const Duration(milliseconds: 250));
      }
      await controller.pause();

      if (gen != _gen || !mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      try {
        await controller?.dispose();
      } catch (_) {}
      if (mounted && gen == _gen) {
        setState(() {
          _failed = true;
          _ready = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    if (_failed || !_ready || _controller == null) {
      return SizedBox(
        width: w,
        height: h,
        child: const ColoredBox(color: Color(0x22000000)),
      );
    }

    final c = _controller!;
    final size = c.value.size;
    final ratio = size.width <= 0 || size.height <= 0
        ? (16 / 9)
        : size.width / size.height;

    return SizedBox(
      width: w,
      height: h,
      child: ClipRect(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: ratio >= 1 ? 160 * ratio : 160,
            height: ratio >= 1 ? 160 : 160 / ratio,
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }
}
