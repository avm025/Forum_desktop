import 'package:flutter/material.dart';

import '../models/message_view_model.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_selection.dart';
import '../utils/voice_histogram.dart';
import '../utils/voice_player.dart';

/// Голосовое как Forum_ios `VoiceMessageCell`:
/// play/pause, реальная гистограмма, прогресс волны, скорость x1…x2.
class VoiceMessage extends StatefulWidget {
  final MessageViewModel message;
  final bool onAccent;
  /// На всю ширину родителя (профиль, широкие пузыри).
  final bool expand;

  const VoiceMessage({
    super.key,
    required this.message,
    this.onAccent = false,
    this.expand = false,
  });

  @override
  State<VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage> {
  bool _starting = false;
  double _speed = 1;
  static const _speeds = [1.0, 1.25, 1.5, 2.0];

  String get _playbackId {
    final id = widget.message.id.trim();
    if (id.isNotEmpty) return id;
    return widget.message.hash.trim();
  }

  @override
  void initState() {
    super.initState();
    VoicePlayer.state.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    VoicePlayer.state.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (!mounted) return;
    final s = VoicePlayer.state.value;
    if (s.messageId == _playbackId && s.speed > 0) {
      _speed = s.speed;
    }
    setState(() {});
  }

  List<int> get _levels {
    final raw = widget.message.voiceHistogram;
    if (raw.isNotEmpty) return raw;
    final dur = _totalSeconds;
    return VoiceHistogram.placeholder(durationSec: dur);
  }

  int get _totalSeconds {
    if (widget.message.files.isNotEmpty &&
        widget.message.files.first.duration > 0) {
      return widget.message.files.first.duration;
    }
    return widget.message.voiceHistogram.length.clamp(1, 3600);
  }

  Future<void> _togglePlay() async {
    AttachmentSelection.suppressNextBubbleTap();
    final playback = VoicePlayer.state.value;
    final isCurrent = playback.messageId == _playbackId;
    // Пауза/resume не блокируем _starting — иначе кнопка «замирает».
    if (isCurrent && !playback.loading) {
      try {
        await VoicePlayer.toggle(widget.message, speed: _speed);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось воспроизвести: $e')),
        );
      }
      return;
    }

    if (_starting) return;
    setState(() => _starting = true);
    try {
      await VoicePlayer.toggle(widget.message, speed: _speed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось воспроизвести: $e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cycleSpeed() async {
    AttachmentSelection.suppressNextBubbleTap();
    final i = _speeds.indexOf(_speed);
    final next = _speeds[(i < 0 ? 0 : i + 1) % _speeds.length];
    setState(() => _speed = next);
    if (VoicePlayer.isCurrent(_playbackId)) {
      await VoicePlayer.setSpeed(next);
    }
  }

  String _speedLabel(double speed) {
    if (speed == 1.25) return 'x1.25';
    if (speed == 1.5) return 'x1.5';
    if (speed == 2) return 'x2';
    return 'x1';
  }

  String _format(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onAccent = widget.onAccent;
    final playback = VoicePlayer.state.value;
    final isCurrent = playback.messageId == _playbackId;
    final playing = isCurrent && playback.playing;
    final loading = isCurrent && (playback.loading || _starting);
    final progress = isCurrent ? playback.progress : 0.0;

    // Как iOS: во время play — прошедшее время; иначе полная длительность.
    final durationText = isCurrent &&
            (playing || playback.position > Duration.zero) &&
            !loading
        ? _format(playback.position)
        : _format(Duration(seconds: _totalSeconds));

    final playColor = onAccent ? p.lime : p.purple;
    final waveBase = onAccent
        ? Colors.white.withValues(alpha: 0.35)
        : p.purple.withValues(alpha: 0.28);
    final wavePlayed = onAccent ? p.lime : p.purple;
    final timeColor = onAccent ? Colors.white.withValues(alpha: 0.85) : p.text2;
    final showSpeed =
        playing || (isCurrent && progress > 0 && progress < 1);

    final content = SizedBox(
      width: widget.expand ? null : 236,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PlayButton(
                color: playColor,
                loading: loading && !playing,
                playing: playing,
                onTap: (loading && !playing) ? null : _togglePlay,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      levels: _levels,
                      progress: progress,
                      baseColor: waveBase,
                      playedColor: wavePlayed,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // Место под чип скорости всегда зарезервировано —
              // иначе при play пузырь «прыгает».
              Opacity(
                opacity: showSpeed ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !showSpeed,
                  child: _SpeedChip(
                    label: _speedLabel(_speed),
                    background: onAccent ? Colors.white : p.purple,
                    foreground: onAccent ? p.purple : Colors.white,
                    onTap: _cycleSpeed,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                durationText,
                style: TextStyle(
                  color: timeColor,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return content;
  }
}

class _PlayButton extends StatelessWidget {
  final Color color;
  final bool loading;
  final bool playing;
  final VoidCallback? onTap;

  const _PlayButton({
    required this.color,
    required this.loading,
    required this.playing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AttachmentSelection.suppressNextBubbleTap();
                  onTap!();
                },
          customBorder: const CircleBorder(),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: color,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: color,
                    size: 34,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<int> levels;
  final double progress;
  final Color baseColor;
  final Color playedColor;

  _WaveformPainter({
    required this.levels,
    required this.progress,
    required this.baseColor,
    required this.playedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.0;
    const gap = 2.0;
    const step = barWidth + gap;
    final barCount = (size.width / step).floor().clamp(16, 96);
    final samples = VoiceHistogram.downsample(levels, barCount);
    final maxVal = samples.fold<int>(1, (a, b) => a > b ? a : b).toDouble();

    final basePaint = Paint()
      ..color = baseColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    final playedPaint = Paint()
      ..color = playedColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final midY = size.height / 2;
    final playX = size.width * progress.clamp(0.0, 1.0);

    for (var i = 0; i < samples.length; i++) {
      final x = barWidth / 2 + i * step;
      if (x > size.width) break;
      // Как DrawOnView: высота пропорциональна уровню (iOS делит на 5 при max≈15).
      var h = size.height * (samples[i] / maxVal) * 0.92;
      if (h < barWidth) h = barWidth;
      final top = midY - h / 2;
      final bottom = midY + h / 2;
      final paint = x <= playX ? playedPaint : basePaint;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) {
    return old.progress != progress ||
        old.baseColor != baseColor ||
        old.playedColor != playedColor ||
        old.levels != levels;
  }
}
