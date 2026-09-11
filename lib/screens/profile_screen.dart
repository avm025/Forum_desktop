import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_forum_image.dart';
import '../widgets/profile_avatar_editor.dart';
import 'appearance_screen.dart';
import 'profile/devices_menu_screen.dart';
import 'profile/edit_profile_screen.dart';
import 'profile/profile_placeholder_screen.dart';
import 'profile/qr_authorize_screen.dart';

enum _ProfileSection {
  appearance,
  privacy,
  notifications,
  language,
  devices,
  premium,
}

/// Вкладка «Профиль» — слева меню, справа выбранный раздел.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  _ProfileSection _section = _ProfileSection.appearance;

  static const _splitBreakpoint = 760.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final isDark = state.isDark;
    final leftBg = isDark ? p.bg1 : const Color(0xFFE8EAED);
    final rightBg = isDark ? p.bg2 : const Color(0xFFF7F8FA);
    final cardBg = isDark ? p.bg2 : Colors.white;
    final separator = isDark ? p.border1 : const Color(0xFFE9E9E9);
    final width = MediaQuery.sizeOf(context).width;
    final split = width >= _splitBreakpoint;

    final leftPane = ColoredBox(
      color: leftBg,
      child: SafeArea(
        right: !split,
        child: _ProfileMenuPane(
          selected: _section,
          cardBg: cardBg,
          separator: separator,
          onSelect: (section) {
            if (split) {
              setState(() => _section = section);
            } else {
              _openSectionFullScreen(context, section);
            }
          },
        ),
      ),
    );

    if (!split) {
      return Scaffold(
        backgroundColor: leftBg,
        body: leftPane,
      );
    }

    return Scaffold(
      backgroundColor: leftBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: (width * 0.38).clamp(280.0, 400.0),
            child: leftPane,
          ),
          Expanded(
            child: ColoredBox(
              color: rightBg,
              child: SafeArea(
                left: false,
                child: KeyedSubtree(
                  key: ValueKey(_section),
                  child: _buildRightPane(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPane() {
    switch (_section) {
      case _ProfileSection.appearance:
        return const AppearanceScreen(embedded: true);
      case _ProfileSection.privacy:
        return const ProfilePlaceholderScreen(
          title: 'Конфиденциальность',
          embedded: true,
        );
      case _ProfileSection.notifications:
        return const ProfilePlaceholderScreen(
          title: 'Уведомления и звуки',
          embedded: true,
        );
      case _ProfileSection.language:
        return const ProfilePlaceholderScreen(
          title: 'Язык',
          embedded: true,
        );
      case _ProfileSection.devices:
        return const DevicesMenuScreen(embedded: true);
      case _ProfileSection.premium:
        return const ProfilePlaceholderScreen(
          title: 'Форум премиум',
          embedded: true,
        );
    }
  }

  void _openSectionFullScreen(BuildContext context, _ProfileSection section) {
    final Widget page;
    switch (section) {
      case _ProfileSection.appearance:
        page = const AppearanceScreen();
      case _ProfileSection.privacy:
        page = const ProfilePlaceholderScreen(title: 'Конфиденциальность');
      case _ProfileSection.notifications:
        page = const ProfilePlaceholderScreen(title: 'Уведомления и звуки');
      case _ProfileSection.language:
        page = const ProfilePlaceholderScreen(title: 'Язык');
      case _ProfileSection.devices:
        page = const DevicesMenuScreen();
      case _ProfileSection.premium:
        page = const ProfilePlaceholderScreen(title: 'Форум премиум');
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _ProfileMenuPane extends StatelessWidget {
  final _ProfileSection selected;
  final Color cardBg;
  final Color separator;
  final ValueChanged<_ProfileSection> onSelect;

  const _ProfileMenuPane({
    required this.selected,
    required this.cardBg,
    required this.separator,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final profile = state.profile;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                const SizedBox(height: 8),
                _OwnProfileHero(profile: profile),
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
                  Text(
                    _about(profile),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.text1,
                      fontSize: 13,
                      height: 1.16,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
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
                  selected: selected == _ProfileSection.appearance,
                  onTap: () => onSelect(_ProfileSection.appearance),
                ),
                _SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'Конфиденциальность',
                  selected: selected == _ProfileSection.privacy,
                  onTap: () => onSelect(_ProfileSection.privacy),
                ),
                _SettingsRow(
                  icon: Icons.notifications_none_rounded,
                  label: 'Уведомления и звуки',
                  selected: selected == _ProfileSection.notifications,
                  onTap: () => onSelect(_ProfileSection.notifications),
                ),
                _SettingsRow(
                  icon: Icons.language_rounded,
                  label: 'Язык',
                  selected: selected == _ProfileSection.language,
                  trailing: Text(
                    'Русский',
                    style: TextStyle(
                      color: p.text3,
                      fontSize: 13,
                    ),
                  ),
                  onTap: () => onSelect(_ProfileSection.language),
                ),
                _SettingsRow(
                  icon: Icons.devices_rounded,
                  label: 'Устройства',
                  selected: selected == _ProfileSection.devices,
                  onTap: () => onSelect(_ProfileSection.devices),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: _PremiumButton(
              selected: selected == _ProfileSection.premium,
              onTap: () => onSelect(_ProfileSection.premium),
            ),
          ),
        ),
      ],
    );
  }

  static String _nick(UserProfile? profile) {
    return profile?.nick.trim() ?? '';
  }

  static String _about(UserProfile? profile) {
    return profile?.about.trim() ?? '';
  }
}

class _OwnProfileHero extends StatelessWidget {
  final UserProfile? profile;

  const _OwnProfileHero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final avatarUrl = profile?.displayAvatarUrl.trim() ?? '';
    final hasAva = avatarUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 285,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasAva)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: CachedForumImage(
                  url: avatarUrl,
                  fit: BoxFit.cover,
                ),
              )
            else
              ColoredBox(color: p.bg3),
            ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
            const Center(
              child: ProfileAvatarEditor(
                size: 112,
                plusSize: 32,
                ringColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
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
  final bool selected;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final highlight = selected
        ? p.purple.withValues(alpha: 0.12)
        : Colors.transparent;

    return Material(
      color: highlight,
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
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
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
  final bool selected;

  const _PremiumButton({
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: selected ? p.purple.withValues(alpha: 0.85) : p.purple,
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
