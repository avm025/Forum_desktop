import 'package:flutter/material.dart';

import '../models/message_view_model.dart';
import '../theme/app_theme.dart';

/// Голосовое сообщение: кнопка play + гистограмма [voiceHistogram] + длительность.
class VoiceMessage extends StatelessWidget {
  final MessageViewModel message;
  final bool onAccent;

  const VoiceMessage({super.key, required this.message, this.onAccent = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = onAccent ? Colors.white : p.purple;
    final barColor = onAccent ? Colors.white54 : p.text3;

    final duration = message.files.isNotEmpty
        ? message.files.first.duration
        : message.voiceHistogram.length;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(Icons.play_arrow_rounded, color: accent, size: 34),
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
                          color: barColor,
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
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
