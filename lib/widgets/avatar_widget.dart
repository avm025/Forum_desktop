import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// Круглый аватар как в Forum iOS `DialogsTableViewCell`:
/// фото, иначе градиент из `ava_col` + инициалы имени.
class AvatarWidget extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final List<String>? avatarColor;
  /// Id палитры (`usr*_col_ava_id` / `grp_col_ava_id`), по умолчанию 1.
  final int colAvaId;
  final double size;
  final bool online;

  const AvatarWidget({
    super.key,
    required this.name,
    this.avatarUrl = '',
    this.avatarColor,
    this.colAvaId = 1,
    this.size = 56,
    this.online = false,
  });

  /// Как iOS: первая буква каждого слова имени.
  String get _initials {
    final words =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final buf = StringBuffer();
    for (final word in words) {
      final chars = word.characters;
      if (chars.isEmpty) continue;
      buf.write(chars.first.toUpperCase());
    }
    final result = buf.toString();
    return result.isEmpty ? '?' : result;
  }

  List<Color> _gradientColors(BuildContext context) {
    // Пара hex с сервера — только если уже градиент из 2 цветов.
    final fromProp = AppColors.parseHexList(avatarColor);
    if (fromProp != null && fromProp.length >= 2) return fromProp;

    try {
      final state = context.read<AppState>();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final id = colAvaId > 0 ? colAvaId : 1;
      final hex = state.appearanceResolver.avatarHexFor(
        isDark: isDark,
        colorId: id,
      );
      if (hex.length >= 2) {
        return [
          AppColors.parseHex(hex[0]),
          AppColors.parseHex(hex[1]),
        ];
      }
      final palette = state.database.avatarById(id);
      if (palette != null) {
        final pair = palette.hexForDark(isDark);
        return [AppColors.parseHex(pair[0]), AppColors.parseHex(pair[1])];
      }
    } catch (_) {
      // Вне Provider — fallback ниже.
    }

    return AppColors.avatarGradientFor(name.isNotEmpty ? name : '$colAvaId');
  }

  Widget _defaultAvatar(List<Color> gradient) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // iOS: горизонтальный градиент (start 0.0 → end 0.2 по X).
        gradient: LinearGradient(
          colors: gradient.length >= 2
              ? gradient
              : [gradient.first, gradient.first],
          begin: Alignment.centerLeft,
          end: const Alignment(0.4, 0),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientColors(context);
    final url = avatarUrl.trim();
    final hasPhoto = url.isNotEmpty;

    Widget avatar;
    if (hasPhoto) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _defaultAvatar(gradient),
          errorWidget: (_, __, ___) => _defaultAvatar(gradient),
        ),
      );
    } else {
      avatar = _defaultAvatar(gradient);
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
