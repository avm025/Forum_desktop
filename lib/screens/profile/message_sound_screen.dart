import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/notification_settings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Пикер звука сообщений → `msg_sound` / `msg_sound_on`.
class MessageSoundScreen extends StatelessWidget {
  final String selectedFile;

  const MessageSoundScreen({super.key, required this.selectedFile});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFEFEFF3);
    final cardBg = state.isDark ? p.bg2 : Colors.white;
    final separator = state.isDark ? p.border1 : const Color(0xFFE4E4E7);
    final current = selectedFile.trim();

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: p.text1,
        centerTitle: true,
        title: Text(
          'Звук сообщений',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'СИСТЕМНЫЕ ЗВУКИ',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < MessageSoundOption.system.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: separator,
                      ),
                    ),
                  _SoundRow(
                    option: MessageSoundOption.system[i],
                    selected: MessageSoundOption.system[i].file == current ||
                        (current.isEmpty &&
                            MessageSoundOption.system[i].file.isEmpty),
                    onTap: () =>
                        Navigator.of(context).pop(MessageSoundOption.system[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundRow extends StatelessWidget {
  final MessageSoundOption option;
  final bool selected;
  final VoidCallback onTap;

  const _SoundRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(color: p.text1, fontSize: 15),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: p.purple, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
