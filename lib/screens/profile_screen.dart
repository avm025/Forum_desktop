import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/appearance_settings.dart';
import '../models/user_profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_avatar_editor.dart';
import 'appearance_screen.dart';

/// Экран профиля пользователя.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final profile = state.profile;

    return Scaffold(
      backgroundColor: p.bg1,
      appBar: AppBar(
        backgroundColor: p.bg1,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Профиль',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                const ProfileAvatarEditor(size: 112),
                const SizedBox(height: 12),
                Text(
                  profile?.name ?? 'Пользователь',
                  style: TextStyle(
                    color: p.text1,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_profileSubtitle(profile).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _profileSubtitle(profile),
                    style: TextStyle(color: p.text2, fontSize: 15),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          _SettingsSection(
            title: 'НАСТРОЙКИ',
            children: [
              _SettingsTile(
                icon: Icons.palette_outlined,
                label: 'Оформление',
                subtitle: _appearanceSubtitle(state),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AppearanceScreen(),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                label: 'Выйти',
                subtitle: 'Сменить аккаунт на этом устройстве',
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Выйти?'),
                      content: const Text(
                        'Вы выйдете из аккаунта на этом устройстве.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Выйти'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await context.read<AppState>().logOut();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _appearanceSubtitle(AppState state) {
    return switch (state.appearance.theme) {
      AppearanceTheme.system => 'Системная тема',
      AppearanceTheme.dark => 'Тёмная тема',
      AppearanceTheme.light => 'Светлая тема',
    };
  }

  static String _profileSubtitle(UserProfile? profile) {
    if (profile == null) return '';
    final parts = <String>[];
    final phone = profile.phone.trim();
    if (phone.isNotEmpty) parts.add(phone);
    final nick = profile.nick.trim();
    if (nick.isNotEmpty) parts.add('@$nick');
    return parts.join(' • ');
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: p.text3,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.bg2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: p.purple, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: p.text2, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.text3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
