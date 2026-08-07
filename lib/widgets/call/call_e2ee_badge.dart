import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_manager.dart';
import '../../theme/app_theme.dart';

/// Индикатор «Сквозное шифрование» (iOS Audio/VideoCallViewController).
class CallE2eeBadge extends StatelessWidget {
  final bool compact;

  const CallE2eeBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<CallManager>().isE2EEEnabled;
    if (!enabled) return const SizedBox.shrink();
    final p = context.palette;
    final color = p.lime;

    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Сквозное шифрование',
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
