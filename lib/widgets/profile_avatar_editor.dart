import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'profile_avatar_picker.dart';

/// Аватар профиля с кнопкой «+» (как в Forum_ios, 32pt).
class ProfileAvatarEditor extends StatelessWidget {
  final double size;
  final double plusSize;
  /// Цвет обводки кнопки «+». На размытом hero — белый, как контраст к баннеру.
  final Color? ringColor;

  const ProfileAvatarEditor({
    super.key,
    this.size = 112,
    this.plusSize = 32,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final profile = state.profile;
    final isDark = state.isDark;
    final uploading = state.profileAvatarUploading;
    final pageBg = isDark ? p.bg1 : const Color(0xFFF4F5F7);
    final ring = ringColor ?? pageBg;
    final colAvaId = profile?.appearance.avatarColorId ?? 1;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        AvatarWidget(
          name: profile?.name ?? '?',
          avatarUrl: profile?.displayAvatarUrl ?? '',
          avatarColor: state.currentUserAvatarHex(isDark: isDark),
          colAvaId: colAvaId,
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
          right: -2,
          bottom: -2,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: uploading ? null : () => showProfileAvatarPicker(context),
              child: Container(
                width: plusSize,
                height: plusSize,
                decoration: BoxDecoration(
                  color: p.purple,
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 3),
                ),
                child: Icon(
                  Icons.add,
                  color: Colors.white,
                  size: plusSize * 0.45,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
