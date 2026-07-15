import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../models/appearance_settings.dart';
import '../models/forum_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Построение палитры и цветов из справочников + настроек пользователя.
class AppearanceResolver {
  const AppearanceResolver({
    required this.database,
    required this.settings,
  });

  final ForumDatabase database;
  final AppearanceSettings settings;

  ForumPalette paletteFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ForumPalette.dark : ForumPalette.light;
    final app = database.appColorById(settings.appColorId);

    final target = app == null
        ? base.purple
        : AppColors.parseHex(isDark ? app.d1 : app.l1);
    final accent = app == null
        ? base.lime
        : AppColors.parseHex(isDark ? app.d2 : app.l2);

    return base.copyWith(
      purple: target,
      lime: accent,
      selectedTile: target,
      outgoingBubble: target,
    );
  }

  Color nameColorFor({required bool isDark, int? colorId}) {
    final id = colorId ?? settings.nameColorId;
    final entry = database.nameColorById(id);
    if (entry == null) return AppColors.purple;
    final hex = isDark ? entry.d : entry.l;
    final alpha = isDark ? entry.dAlpha : entry.lAlpha;
    return AppColors.parseHex(hex).withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  List<String> avatarHexFor({required bool isDark, int? colorId}) {
    final id = colorId ?? settings.avatarColorId;
    final entry = database.avatarById(id);
    if (entry == null) return const [];
    return entry.hexForDark(isDark);
  }

  String? chatBackgroundUrl({required bool isDark}) {
    final raw = settings.bgImg.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.fileUrl('', raw.startsWith('/') ? raw.substring(1) : raw);
  }

  List<ChatBackgroundOption> backgroundsFor(bool isDark) =>
      database.backgroundsFor(isDark);
}
