import 'dart:async';
import 'dart:io';

import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

/// Результат записи круглого видеосообщения.
class VideoNoteResult {
  final String path;
  final int durationSec;

  const VideoNoteResult({required this.path, required this.durationSec});
}

/// Диалог записи видеосообщения (как кружок в Telegram) для macOS.
class VideoNoteRecorder {
  VideoNoteRecorder._();

  static Future<VideoNoteResult?> show(BuildContext context) {
    if (!Platform.isMacOS) return Future.value(null);
    return showDialog<VideoNoteResult>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => const _VideoNoteDialog(),
    );
  }
}

class _VideoNoteDialog extends StatefulWidget {
  const _VideoNoteDialog();

  @override
  State<_VideoNoteDialog> createState() => _VideoNoteDialogState();
}

class _VideoNoteDialogState extends State<_VideoNoteDialog> {
  CameraMacOSController? _controller;
  bool _ready = false;
  bool _recording = false;
  bool _busy = false;
  String? _error;
  DateTime? _startedAt;
  Timer? _tick;
  int _elapsed = 0;

  static const _maxSec = 60;

  @override
  void dispose() {
    _tick?.cancel();
    final c = _controller;
    if (c != null) {
      unawaited(c.destroy());
    }
    super.dispose();
  }

  void _onReady(CameraMacOSController controller) {
    _controller = controller;
    setState(() {
      _ready = true;
      _error = null;
    });
    unawaited(_beginRecord());
  }

  Future<void> _beginRecord() async {
    final c = _controller;
    if (c == null || _recording || _busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/video_note_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ok = await c.recordVideo(
        maxVideoDuration: _maxSec.toDouble(),
        url: path,
        enableAudio: true,
        onVideoRecordingFinished: (file, err) {
          if (!mounted) return;
          if (err != null || file == null) return;
          _finishWithFile(file, auto: true);
        },
      );
      if (ok != true) {
        setState(() {
          _error = 'Не удалось начать запись';
          _busy = false;
        });
        return;
      }
      _startedAt = DateTime.now();
      _elapsed = 0;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _startedAt == null) return;
        setState(() {
          _elapsed = DateTime.now().difference(_startedAt!).inSeconds;
        });
      });
      setState(() {
        _recording = true;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _cancel() async {
    final c = _controller;
    if (c != null && _recording) {
      try {
        await c.stopRecording();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stopAndSend() async {
    final c = _controller;
    if (c == null || !_recording || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.stopRecording();
      await _finishWithFile(file, auto: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
        _recording = false;
      });
    }
  }

  Future<void> _finishWithFile(CameraMacOSFile? file, {required bool auto}) async {
    _tick?.cancel();
    final sec = (_startedAt == null
            ? _elapsed
            : DateTime.now().difference(_startedAt!).inSeconds)
        .clamp(1, _maxSec);
    if (file == null) {
      if (mounted) {
        setState(() {
          _error = 'Пустая запись';
          _busy = false;
          _recording = false;
        });
      }
      return;
    }

    String? path = file.url;
    if ((path == null || path.isEmpty) && file.bytes != null) {
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/video_note_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(path).writeAsBytes(file.bytes!, flush: true);
    }
    if (path == null || path.isEmpty || !mounted) return;
    if (sec < 1) {
      setState(() {
        _error = 'Слишком короткое видео';
        _busy = false;
        _recording = false;
      });
      return;
    }
    Navigator.of(context).pop(VideoNoteResult(path: path, durationSec: sec));
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Material(
        color: p.bg1,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Видеосообщение',
                style: TextStyle(
                  color: p.text1,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 260,
                height: 260,
                child: ClipOval(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraMacOSView(
                          fit: BoxFit.cover,
                          cameraMode: CameraMacOSMode.video,
                          enableAudio: true,
                          onCameraInizialized: _onReady,
                        ),
                        if (!_ready)
                          const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (_recording)
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _fmt(_elapsed),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text('Отмена', style: TextStyle(color: p.text2)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: (!_recording || _busy) ? null : _stopAndSend,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Отправить'),
                    style: FilledButton.styleFrom(backgroundColor: p.purple),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
