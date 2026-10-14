import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/notification_settings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'message_sound_screen.dart';

/// «Уведомления и звуки» — раскладка как в Telegram Desktop.
/// Серверные флаги — WS `device` msg_* ([api_forum_doc] device).
class NotificationsSoundsScreen extends StatefulWidget {
  final bool embedded;

  const NotificationsSoundsScreen({super.key, this.embedded = false});

  @override
  State<NotificationsSoundsScreen> createState() =>
      _NotificationsSoundsScreenState();
}

class _NotificationsSoundsScreenState extends State<NotificationsSoundsScreen> {
  /// Синий переключатель как в Telegram Desktop.
  static const _tgBlue = Color(0xFF2481CC);

  Future<void> _set(NotificationSettings next) async {
    final err =
        await context.read<AppState>().saveNotificationSettings(next);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить настройки?'),
        content: const Text(
          'Все настройки уведомлений на этом устройстве будут возвращены к значениям по умолчанию.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().resetNotificationSettings();
    }
  }

  Future<void> _openSoundPicker(NotificationSettings s) async {
    final selected = await Navigator.of(context).push<MessageSoundOption>(
      MaterialPageRoute(
        builder: (_) => MessageSoundScreen(selectedFile: s.soundFile),
      ),
    );
    if (selected == null || !mounted) return;
    await _set(
      s.copyWith(
        soundFile: selected.file,
        soundOn: selected.file.isNotEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.notificationSettings;
    final p = context.palette;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFEFEFF3);
    final cardBg = state.isDark ? p.bg2 : Colors.white;
    final separator = state.isDark ? p.border1 : const Color(0xFFE4E4E7);
    final footnote = state.isDark ? p.text3 : const Color(0xFF8E8E93);
    final showDock = !Platform.isLinux; // macOS / Windows Dock-like

    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _SectionLabel('УВЕДОМЛЕНИЯ'),
        _SettingsCard(
          cardBg: cardBg,
          separator: separator,
          children: [
            _ToggleRow(
              label: 'Уведомления',
              value: s.pushOn,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(pushOn: v)),
            ),
            _ToggleRow(
              label: 'Предпросмотр сообщений',
              value: s.messagePreview,
              activeColor: _tgBlue,
              onChanged: (v) => _set(
                s.copyWith(
                  messagePreview: v,
                  namesInNotifications: v,
                ),
              ),
            ),
            _NavRow(
              label: 'Звук сообщений',
              value: s.soundDisplayName,
              onTap: () => _openSoundPicker(s),
            ),
            if (showDock)
              _ToggleRow(
                label: 'Анимация иконки в панели Dock',
                value: s.dockBounce,
                activeColor: _tgBlue,
                onChanged: (v) => _set(s.copyWith(dockBounce: v)),
              ),
            _ActionRow(
              label: 'Сбросить настройки уведомлений',
              color: p.purple,
              onTap: _reset,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel('ПРИНИМАТЬ НА ЭТОМ УСТРОЙСТВЕ'),
        _SettingsCard(
          cardBg: cardBg,
          separator: separator,
          children: [
            _ToggleRow(
              label: 'Новые секретные чаты',
              value: s.secretChats,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(secretChats: v)),
            ),
            _ToggleRow(
              label: 'Входящие звонки',
              value: s.incomingCalls,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(incomingCalls: v)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel('ЗВУКОВЫЕ ЭФФЕКТЫ'),
        _SettingsCard(
          cardBg: cardBg,
          separator: separator,
          children: [
            _ToggleRow(
              label: 'Отправленное сообщение',
              value: s.sentMessageSound,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(sentMessageSound: v)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel('СЧЁТЧИК НА ИКОНКЕ'),
        _SettingsCard(
          cardBg: cardBg,
          separator: separator,
          children: [
            _ToggleRow(
              label: 'Включён',
              value: s.badgeEnabled,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(badgeEnabled: v)),
            ),
            _ToggleRow(
              label: 'Включить группы',
              value: s.badgeIncludeGroups,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(badgeIncludeGroups: v)),
            ),
            _ToggleRow(
              label: 'Каналы',
              value: s.badgeIncludeChannels,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(badgeIncludeChannels: v)),
            ),
            _ToggleRow(
              label: 'Число сообщений',
              value: s.badgeCountMessages,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(badgeCountMessages: v)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Когда выключено, счётчик показывает число непрочитанных чатов, а не число сообщений.',
            style: TextStyle(color: footnote, fontSize: 13, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        _SettingsCard(
          cardBg: cardBg,
          separator: separator,
          children: [
            _ToggleRow(
              label: 'Новые контакты',
              value: s.newContacts,
              activeColor: _tgBlue,
              onChanged: (v) => _set(s.copyWith(newContacts: v)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Показывать уведомление, когда кто-то из списка контактов регистрируется в Forum.',
            style: TextStyle(color: footnote, fontSize: 13, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('КОГДА ПРИЛОЖЕНИЕ АКТИВНО'),
        _SettingsCard(
          cardBg: cardBg,
          separator: separator,
          children: [
            _ToggleRow(
              label: 'Показывать уведомления',
              value: s.showWhenAppActive,
              activeColor: _tgBlue,
              onChanged: (v) => _set(
                s.copyWith(
                  showWhenAppActive: v,
                  // Вкл. — также разрешаем pop-ups на сервере.
                  popUpsOn: v ? true : s.popUpsOn,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Выключите, чтобы не показывать баннеры, пока окно Forum активно.',
            style: TextStyle(color: footnote, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );

    final header = SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (!widget.embedded)
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: p.text1,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Уведомления',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.text1,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: pageBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: list),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: list),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Color cardBg;
  final Color separator;
  final List<Widget> children;

  const _SettingsCard({
    required this.cardBg,
    required this.separator,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Divider(height: 0.5, thickness: 0.5, color: separator),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: p.text1, fontSize: 15),
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: Colors.white,
              activeTrackColor: activeColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _NavRow({
    required this.label,
    required this.value,
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
                  label,
                  style: TextStyle(color: p.text1, fontSize: 15),
                ),
              ),
              Text(
                value,
                style: TextStyle(color: p.text3, fontSize: 15),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: p.text3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionRow({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}
