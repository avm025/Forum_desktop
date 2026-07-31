import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class CallControlsBar extends StatelessWidget {
  final bool micOn;
  final bool camOn;
  final bool speakerOn;
  final bool showCamera;
  final bool showSwitchCamera;
  final bool showRecord;
  final bool showInvite;
  final bool recording;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleCam;
  final VoidCallback? onToggleSpeaker;
  final VoidCallback? onSwitchCamera;
  final VoidCallback? onToggleRecord;
  final VoidCallback? onInvite;
  final VoidCallback? onHangup;

  const CallControlsBar({
    super.key,
    required this.micOn,
    required this.camOn,
    required this.speakerOn,
    this.showCamera = true,
    this.showSwitchCamera = false,
    this.showRecord = false,
    this.showInvite = false,
    this.recording = false,
    this.onToggleMic,
    this.onToggleCam,
    this.onToggleSpeaker,
    this.onSwitchCamera,
    this.onToggleRecord,
    this.onInvite,
    this.onHangup,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 12,
        children: [
          _RoundCallButton(
            icon: micOn ? Icons.mic : Icons.mic_off,
            label: 'Микрофон',
            active: micOn,
            onTap: onToggleMic,
          ),
          if (showCamera)
            _RoundCallButton(
              icon: camOn ? Icons.videocam : Icons.videocam_off,
              label: 'Камера',
              active: camOn,
              onTap: onToggleCam,
            ),
          if (showSwitchCamera)
            _RoundCallButton(
              icon: Icons.cameraswitch,
              label: 'Камера',
              onTap: onSwitchCamera,
            ),
          _RoundCallButton(
            icon: speakerOn ? Icons.volume_up : Icons.volume_off,
            label: 'Динамик',
            active: speakerOn,
            onTap: onToggleSpeaker,
          ),
          if (showInvite)
            _RoundCallButton(
              icon: Icons.person_add_alt_1,
              label: 'Пригласить',
              onTap: onInvite,
            ),
          if (showRecord)
            _RoundCallButton(
              icon: Icons.fiber_manual_record,
              label: 'Запись',
              active: recording,
              activeColor: Colors.redAccent,
              onTap: onToggleRecord,
            ),
          _RoundCallButton(
            icon: Icons.call_end,
            label: 'Завершить',
            destructive: true,
            onTap: onHangup,
          ),
        ],
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool destructive;
  final Color? activeColor;
  final VoidCallback? onTap;

  const _RoundCallButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.destructive = false,
    this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = destructive
        ? Colors.redAccent
        : (active
            ? (activeColor ?? p.purple)
            : Colors.white.withValues(alpha: 0.12));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
