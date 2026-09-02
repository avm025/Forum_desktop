import 'package:flutter/material.dart';

import '../models/message_view_model.dart';
import '../theme/app_theme.dart';
import '../utils/voice_player.dart';

/// Голосовое сообщение: play/pause + гистограмма + длительность.
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    VoicePlayer.playingMessageId.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    VoicePlayer.playingMessageId.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await VoicePlayer.toggle(widget.message);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось воспроизвести')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onAccent = widget.onAccent;
    final accent = onAccent ? Colors.white : p.purple;
    final barColor = onAccent ? Colors.white54 : p.text3;
    final message = widget.message;

    final duration = message.files.isNotEmpty
        ? message.files.first.duration
        : message.voiceHistogram.length;

    final playing = VoicePlayer.isPlaying(message.id);

    final content = InkWell(
      onTap: _busy ? null : _togglePlay,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          if (_busy)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent,
              ),
            )
          else
            Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: accent,
              size: 34,
            ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final h in message.voiceHistogram)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.6),
                        height: (h.clamp(2, 24)).toDouble(),
                        decoration: BoxDecoration(
                          color: playing
                              ? accent.withValues(alpha: 0.65)
                              : barColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _format(duration),
            style: TextStyle(
              color: onAccent ? Colors.white70 : p.text2,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    if (widget.expand) return content;
    return SizedBox(width: 220, child: content);
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
