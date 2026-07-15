import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Дополнительные семантические цвета, недоступные в стандартной [ThemeData].
@immutable
class ForumPalette extends ThemeExtension<ForumPalette> {
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color border1;
  final Color border2;
  final Color text1;
  final Color text2;
  final Color text3;
  final Color purple;
  final Color lime;
  final Color selectedTile;
  final Color outgoingBubble;

  const ForumPalette({
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.border1,
    required this.border2,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.purple,
    required this.lime,
    required this.selectedTile,
    required this.outgoingBubble,
  });

  static const ForumPalette dark = ForumPalette(
    bg1: AppColors.darkBg1,
    bg2: AppColors.darkBg2,
    bg3: AppColors.darkBg3,
    border1: AppColors.darkBorder1,
    border2: AppColors.darkBorder2,
    text1: AppColors.darkText1,
    text2: AppColors.darkText2,
    text3: AppColors.darkText3,
    purple: AppColors.purple,
    lime: AppColors.lime,
    selectedTile: AppColors.purple,
    outgoingBubble: AppColors.purple,
  );

  static const ForumPalette light = ForumPalette(
    bg1: AppColors.lightBg1,
    bg2: AppColors.lightBg2,
    bg3: AppColors.lightBg3,
    border1: AppColors.lightBorder1,
    border2: AppColors.lightBorder2,
    text1: AppColors.lightText1,
    text2: AppColors.lightText2,
    text3: AppColors.lightText3,
    purple: AppColors.purple,
    lime: Color(0xFF3FB950),
    selectedTile: AppColors.purple,
    outgoingBubble: AppColors.purple,
  );

  @override
  ForumPalette copyWith({
    Color? bg1,
    Color? bg2,
    Color? bg3,
    Color? border1,
    Color? border2,
    Color? text1,
    Color? text2,
    Color? text3,
    Color? purple,
    Color? lime,
    Color? selectedTile,
    Color? outgoingBubble,
  }) {
    return ForumPalette(
      bg1: bg1 ?? this.bg1,
      bg2: bg2 ?? this.bg2,
      bg3: bg3 ?? this.bg3,
      border1: border1 ?? this.border1,
      border2: border2 ?? this.border2,
      text1: text1 ?? this.text1,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      purple: purple ?? this.purple,
      lime: lime ?? this.lime,
      selectedTile: selectedTile ?? this.selectedTile,
      outgoingBubble: outgoingBubble ?? this.outgoingBubble,
    );
  }

  @override
  ForumPalette lerp(ThemeExtension<ForumPalette>? other, double t) {
    if (other is! ForumPalette) return this;
    return ForumPalette(
      bg1: Color.lerp(bg1, other.bg1, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      bg3: Color.lerp(bg3, other.bg3, t)!,
      border1: Color.lerp(border1, other.border1, t)!,
      border2: Color.lerp(border2, other.border2, t)!,
      text1: Color.lerp(text1, other.text1, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      selectedTile: Color.lerp(selectedTile, other.selectedTile, t)!,
      outgoingBubble: Color.lerp(outgoingBubble, other.outgoingBubble, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'SF Pro Display';

  static ThemeData dark() => build(Brightness.dark, ForumPalette.dark);
  static ThemeData light() => build(Brightness.light, ForumPalette.light);

  static ThemeData build(Brightness brightness, ForumPalette p) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg1,
      canvasColor: p.bg1,
      colorScheme: base.colorScheme.copyWith(
        primary: p.purple,
        secondary: p.lime,
        surface: p.bg1,
      ),
      extensions: <ThemeExtension<dynamic>>[p],
      textTheme: base.textTheme.apply(
        bodyColor: p.text1,
        displayColor: p.text1,
      ),
      dividerColor: p.border1,
      iconTheme: IconThemeData(color: p.text1),
    );
  }
}

/// Удобный доступ к [ForumPalette] из контекста.
extension ForumThemeContext on BuildContext {
  ForumPalette get palette =>
      Theme.of(this).extension<ForumPalette>() ?? ForumPalette.dark;
}
