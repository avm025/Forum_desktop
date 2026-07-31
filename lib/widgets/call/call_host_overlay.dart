import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_manager.dart';
import '../../calls/call_models.dart';
import '../../theme/app_theme.dart';
import 'call_invite_sheet.dart';
import 'call_screens.dart';

/// Оверлей входящего звонка + полноэкранный активный звонок.
class CallHostOverlay extends StatelessWidget {
  final Widget child;

  const CallHostOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallManager>();
    final incoming = calls.incoming;
    final session = calls.session;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (incoming != null) _IncomingBanner(invite: incoming),
        if (session != null &&
            session.state != CallState.ended &&
            session.state != CallState.idle)
          Positioned.fill(
            child: session.isGroup
                ? const GroupCallScreen()
                : (session.wantsVideo || calls.camEnabled
                    ? const VideoCallScreen()
                    : const AudioCallScreen()),
          ),
        // Поверх звонка: нет Navigator в builder → sheet без showModalBottomSheet.
        if (calls.invitePickerOpen) const Positioned.fill(child: CallInviteSheet()),
      ],
    );
  }
}

class _IncomingBanner extends StatelessWidget {
  final IncomingCallInvite invite;

  const _IncomingBanner({required this.invite});

  @override
  Widget build(BuildContext context) {
    final calls = context.read<CallManager>();
    final p = context.palette;
    final title = invite.title.isNotEmpty
        ? invite.title
        : (invite.callerName.isNotEmpty ? invite.callerName : 'Входящий звонок');

    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: p.bg2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.border1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                invite.video ? Icons.videocam : Icons.call,
                color: p.purple,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                invite.isGroup ? 'Групповой звонок' : 'Входящий звонок',
                style: TextStyle(color: p.text2, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.text1,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: calls.declineIncoming,
                      child: const Text('Отклонить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF34C759),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () =>
                          calls.acceptIncoming(withVideo: invite.video),
                      child: const Text('Принять'),
                    ),
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
