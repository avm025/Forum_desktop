import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
// Windows-бэкенд для video_player (официально Windows не поддерживается).
// ignore: unused_import
import 'package:video_player_win/video_player_win.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../utils/file_opener.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';
import '../utils/media_viewer_context.dart';
import '../utils/native_media_overlay.dart';
import 'telegram_media_loader.dart';
import 'telegram_media_overlay.dart';

/// Видео на размытом фоне. На macOS — отдельное окно на весь монитор.
class FullscreenVideoViewer extends StatefulWidget {
  final MediaFile file;
  final MediaViewerContext? viewerContext;

  const FullscreenVideoViewer({
    super.key,
    required this.file,
    this.viewerContext,
  });

  static Future<void> show(
    BuildContext context,
    MediaFile file, {
    MediaViewerContext? viewerContext,
    Future<void> Function(String action)? onOverlayAction,
  }) async {
    if (await NativeMediaOverlay.showFile(
      file,
      context: viewerContext,
      onAction: onOverlayAction,
    )) {
      return;
    }
    if (!context.mounted) return;
    await TelegramMediaOverlay.show(
      context: context,
      builder: (_) => FullscreenVideoViewer(
        file: file,
        viewerContext: viewerContext,
      ),
    );
  }

  @override
  State<FullscreenVideoViewer> createState() => _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends State<FullscreenVideoViewer> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;
  double? _progress;
  String _status = 'Загрузка…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initPlayer();
    });
  }

  Future<void> _initPlayer() async {
    try {
      final downloadUrl = MediaFileUrl.resolve(widget.file);

      final cached = await MediaFileLoader.cachedPathIfExists(
        widget.file,
        downloadUrl: downloadUrl,
      );
      if (cached != null) {
        await _playLocal(cached);
        return;
      }

      final localPath = widget.file.URL?.trim() ?? '';
      if (localPath.isNotEmpty &&
          !localPath.startsWith('http') &&
          File(localPath).existsSync()) {
        await _playLocal(localPath);
        return;
      }

      if (downloadUrl.startsWith('http://') ||
          downloadUrl.startsWith('https://')) {
        if (mounted) {
          setState(() {
            _status = 'Подключение…';
            _progress = null;
          });
        }
        final streamed = await _tryPlayNetwork(downloadUrl);
        if (streamed) return;

        if (mounted) {
          setState(() {
            _status = 'Скачивание…';
            _progress = 0;
          });
        }
        final path = await MediaFileLoader.ensureCached(
          widget.file,
          downloadUrl: downloadUrl,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p;
              if (p != null) {
                _status = 'Скачивание ${(p * 100).round()}%';
              }
            });
          },
        );
        await _playLocal(path);
        return;
      }

      throw StateError('Нет URL видео');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<bool> _tryPlayNetwork(String url) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(ApiConfig.rewriteLegacyHost(url)),
        httpHeaders: ApiConfig.fileHeaders,
      );
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) {
        await controller.dispose();
        return false;
      }
      if (!controller.value.isInitialized) {
        await controller.dispose();
        return false;
      }
      if (controller.value.hasError) {
        await controller.dispose();
        return false;
      }
      controller.addListener(_onTick);
      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
      await controller.play();
      return true;
    } catch (_) {
      try {
        await controller?.dispose();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _playLocal(String localPath) async {
    if (mounted) {
      setState(() {
        _status = 'Открытие…';
        _progress = null;
      });
    }
    final file = File(localPath);
    if (!await file.exists() || await file.length() <= 0) {
      throw StateError('Локальный файл пуст');
    }
    final controller = VideoPlayerController.file(file);
    await controller.initialize().timeout(const Duration(seconds: 20));
    if (!mounted) {
      controller.dispose();
      return;
    }
    if (!controller.value.isInitialized || controller.value.hasError) {
      await controller.dispose();
      throw StateError(
        controller.value.errorDescription ??
            'Плеер не смог открыть файл (кодек?)',
      );
    }
    controller.addListener(_onTick);
    setState(() {
      _controller = controller;
      _loading = false;
      _error = null;
    });
    await controller.play();
  }

  Future<void> _openExternally() async {
    final opened = await FileOpener.open(widget.file);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть видео')),
      );
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _controller != null && _controller!.value.isInitialized && !_loading;

    return TelegramMediaOverlayShell(
      // На Windows без крестика оверлей «залипает» — Esc/тап мимо неочевидны.
      showCloseButton: true,
      viewerContext: widget.viewerContext,
      bottomBar: ready
          ? Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _controls(),
              ),
            )
          : null,
      child: _mediaBody(context),
    );
  }

  Widget _mediaBody(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width - 48;
    final maxH = size.height - 160;

    final thumb = MediaThumbCache.peekSync(widget.file);
    Widget? thumbWidget;
    if (thumb != null) {
      thumbWidget = Image.file(
        thumb,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }

    if (_loading) {
      return SizedBox(
        width: maxW.clamp(200, 640),
        height: maxH.clamp(160, 400),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (thumbWidget != null) thumbWidget,
            const ColoredBox(color: Color(0x66000000)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TelegramMediaLoadingOverlay(progress: _progress, size: 64),
                const SizedBox(height: 14),
                Text(
                  _status,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Не удалось воспроизвести видео\n$_error',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _openExternally,
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                  label: const Text(
                    'Открыть в плеере Windows',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: _close,
                  child: const Text(
                    'Закрыть',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final c = _controller!;
    final ratio = c.value.aspectRatio == 0 ? (16 / 9) : c.value.aspectRatio;
    return GestureDetector(
      onTap: _togglePlay,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final c = _controller!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: _togglePlay,
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
              IconButton(
                tooltip: 'Открыть снаружи',
                icon: const Icon(Icons.open_in_new, color: Colors.white70),
                onPressed: _openExternally,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
