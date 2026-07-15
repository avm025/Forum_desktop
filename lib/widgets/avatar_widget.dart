import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'cached_forum_image.dart';

/// Круглый аватар: фото (если есть), иначе градиент + инициалы.
class AvatarWidget extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final List<String>? avatarColor;
  final double size;
  final bool online;

  const AvatarWidget({
    super.key,
    required this.name,
    this.avatarUrl = '',
    this.avatarColor,
    this.size = 56,
    this.online = false,
  });

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final gradient =
        AppColors.parseHexList(avatarColor) ?? AppColors.avatarGradientFor(name);
    final hasPhoto = avatarUrl.isNotEmpty;

    Widget avatar;
    if (hasPhoto) {
      avatar = ClipOval(
        child: CachedForumImage(
          url: avatarUrl,
          width: size,
          height: size,
        ),
      );
    } else {
      avatar = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: gradient.length >= 2
                ? gradient
                : [gradient.first, gradient.first],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (!online) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: AppColors.lime,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.darkBg1, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
