import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_avatar_editor.dart';
import 'appearance_screen.dart';
import 'profile/devices_menu_screen.dart';
import 'profile/edit_profile_screen.dart';
import 'profile/profile_placeholder_screen.dart';
import 'profile/qr_authorize_screen.dart';

/// Вкладка «Профиль» — как в Forum_ios `ProfileViewController`.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final profile = state.profile;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFF4F5F7);
    final cardBg = state.isDark ? p.bg2 : Colors.white;
    final separator = state.isDark ? p.border1 : const Color(0xFFE9E9E9);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Скан QR слева сверху — как qrAuthBarButton в Forum_ios.
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const QrAuthorizeScreen(),
                          ),
                        );
                      },
                      tooltip: 'Авторизовать по QR-коду',
                      icon: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: p.purple,
                        size: 24,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        );
                      },
                      tooltip: 'Редактировать',
                      icon: Icon(
                        Icons.edit_outlined,
                        color: p.purple,
                        size: 24,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  const ProfileAvatarEditor(size: 112, plusSize: 32),
                  const SizedBox(height: 16),
                  Text(
                    profile?.name.trim().isNotEmpty == true
                        ? profile!.name
                        : 'Пользователь',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.text1,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_nick(profile).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _CopyNickButton(nick: _nick(profile)),
                  ],
                  if (_about(profile).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _about(profile),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.text1,
                          fontSize: 13,
                          height: 1.16,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SettingsCard(
                  background: cardBg,
                  separator: separator,
                  children: [
                    _SettingsRow(
                      icon: Icons.palette_outlined,
                      label: 'Оформление',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AppearanceScreen(),
                          ),
                        );
                      },
                    ),
                    _SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      label: 'Конфиденциальность',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ProfilePlaceholderScreen(
                              title: 'Конфиденциальность',
                            ),
                          ),
                        );
                      },
                    ),
                    _SettingsRow(
                      icon: Icons.notifications_none_rounded,
                      label: 'Уведомления и звуки',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ProfilePlaceholderScreen(
                              title: 'Уведомления и звуки',
                            ),
                          ),
                        );
                      },
                    ),
                    _SettingsRow(
                      icon: Icons.language_rounded,
                      label: 'Язык',
                      trailing: Text(
                        'Русский',
                        style: TextStyle(
                          color: p.text3,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ProfilePlaceholderScreen(
                              title: 'Язык',
                            ),
                          ),
                        );
                      },
                    ),
                    _SettingsRow(
                      icon: Icons.devices_rounded,
                      label: 'Устройства',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DevicesMenuScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: _PremiumButton(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfilePlaceholderScreen(
                          title: 'Форум премиум',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _nick(UserProfile? profile) {
    final nick = profile?.nick.trim() ?? '';
    return nick;
  }

  static String _about(UserProfile? profile) {
    return profile?.about.trim() ?? '';
  }
}

class _CopyNickButton extends StatelessWidget {
  final String nick;

  const _CopyNickButton({required this.nick});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = nick.startsWith('@') ? nick : '@$nick';

    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: nick.replaceFirst('@', '')));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ник скопирован'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: p.text2,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 14, color: p.text3),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Color background;
  final Color separator;
  final List<Widget> children;

  const _SettingsCard({
    required this.background,
    required this.separator,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Divider(height: 0.5, thickness: 0.5, color: separator),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: p.lime, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: p.text1,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  trailing!,
                  const SizedBox(width: 10),
                ],
                Icon(Icons.chevron_right, color: p.purple, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PremiumButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.purple,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          height: 50,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Форум премиум',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'от 159 ₽ / мес.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
