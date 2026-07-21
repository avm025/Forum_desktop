import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_avatar_editor.dart';

/// Редактирование профиля — как в Forum_ios `EditProfileViewController`
/// (упрощённый UI: аватар, поля, выход).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _nick;
  late final TextEditingController _about;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AppState>().profile;
    _name = TextEditingController(text: profile?.name ?? '');
    final nick = profile?.nick.trim() ?? '';
    _nick = TextEditingController(
      text: nick.isEmpty ? '' : (nick.startsWith('@') ? nick : '@$nick'),
    );
    _about = TextEditingController(text: profile?.about ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _nick.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _logOut() async {
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
    if (ok == true && mounted) {
      await context.read<AppState>().logOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFF4F5F7);
    final cardBg = state.isDark ? p.bg2 : Colors.white;
    final phone = state.profile?.phone.trim() ?? '';

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: p.text1,
        centerTitle: true,
        title: Text(
          'Редактировать профиль',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Center(child: ProfileAvatarEditor(size: 112, plusSize: 32)),
          const SizedBox(height: 24),
          _FieldCard(
            background: cardBg,
            child: Column(
              children: [
                _EditField(
                  controller: _name,
                  hint: 'Имя',
                  enabled: false,
                ),
                Divider(height: 0.5, thickness: 0.5, color: p.border1),
                _EditField(
                  controller: _nick,
                  hint: '@ник',
                  enabled: false,
                ),
                Divider(height: 0.5, thickness: 0.5, color: p.border1),
                _EditField(
                  controller: _about,
                  hint: 'О себе',
                  enabled: false,
                  maxLines: 3,
                ),
              ],
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FieldCard(
              background: cardBg,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    phone.startsWith('+') ? phone : '+$phone',
                    style: TextStyle(color: p.purple, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Material(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _logOut,
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                height: 46,
                child: Center(
                  child: Text(
                    'Выйти',
                    style: TextStyle(
                      color: Color(0xFFE5484D),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  final Color background;
  final Widget child;

  const _FieldCard({required this.background, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int maxLines;

  const _EditField({
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        style: TextStyle(color: p.text1, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.text3, fontSize: 15),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
