import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'profile_avatar_picker.dart';

/// Аватар профиля с кнопкой смены фото.
class ProfileAvatarEditor extends StatelessWidget {
  final double size;

  const ProfileAvatarEditor({super.key, this.size = 112});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final profile = state.profile;
    final isDark = state.isDark;
    final uploading = state.profileAvatarUploading;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AvatarWidget(
          name: profile?.name ?? '?',
          avatarUrl: profile?.displayAvatarUrl ?? '',
          avatarColor: state.currentUserAvatarHex(isDark: isDark),
          size: size,
        ),
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: p.purple,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: uploading ? null : () => showProfileAvatarPicker(context),
              child: SizedBox(
                width: size * 0.32,
                height: size * 0.32,
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: size * 0.17,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
