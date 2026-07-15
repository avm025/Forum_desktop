import 'package:flutter/material.dart';

/// Цветовые токены из макета Figma "Форум (web step)".
class AppColors {
  AppColors._();

  // --- Тёмная тема (основная) ---
  /// Целевое действие / выделение / имена отправителей.
  static const Color purple = Color(0xFF904FFF);

  /// Акцент: активные табы, бейджи, онлайн, прочитанные галочки, избранное.
  static const Color lime = Color(0xFF9BFF4B);

  static const Color darkBg1 = Color(0xFF0D0D0D); // фон списка/приложения
  static const Color darkBg2 = Color(0xFF1C1C1C); // карточки/поля
  static const Color darkBg3 = Color(0xFF262626); // приподнятые поверхности
  static const Color darkBorder1 = Color(0xFF2E2E2E);
  static const Color darkBorder2 = Color(0xFF525252);
  static const Color darkText1 = Color(0xFFFFFFFF);
  static const Color darkText2 = Color(0xFF999999);
  static const Color darkText3 = Color(0xFF666666);

  // --- Светлая тема ---
  static const Color lightBg1 = Color(0xFFFFFFFF);
  static const Color lightBg2 = Color(0xFFF2F2F2);
  static const Color lightBg3 = Color(0xFFE9E9EB);
  static const Color lightBorder1 = Color(0xFFE0E0E0);
  static const Color lightBorder2 = Color(0xFFC7C7CC);
  static const Color lightText1 = Color(0xFF0D0D0D);
  static const Color lightText2 = Color(0xFF666666);
  static const Color lightText3 = Color(0xFF999999);

  /// Палитра градиентов для аватаров (из массива цветов слоёв Форум).
  static const List<List<Color>> avatarGradients = [
    [Color(0xFF904FFF), Color(0xFF5B36C9)], // фиолетовый
    [Color(0xFF3B82F6), Color(0xFF22D3EE)], // синий → голубой
    [Color(0xFFFF7A45), Color(0xFFFF4D4F)], // оранжевый → красный
    [Color(0xFF22C55E), Color(0xFF14B8A6)], // зелёный → бирюзовый
    [Color(0xFFEC4899), Color(0xFFF43F5E)], // розовый
    [Color(0xFFF59E0B), Color(0xFFEF4444)], // янтарный
    [Color(0xFF8B5CF6), Color(0xFF3B82F6)], // фиол → синий
    [Color(0xFF06B6D4), Color(0xFF3B82F6)], // циан → синий
  ];

  /// Подобрать пару цветов для аватара по имени/идентификатору.
  static List<Color> avatarGradientFor(String seed) {
    if (seed.isEmpty) return avatarGradients.first;
    final index = seed.codeUnits.fold<int>(0, (a, b) => a + b) %
        avatarGradients.length;
    return avatarGradients[index];
  }

  /// Преобразовать hex-строки из `avatarColor` в Flutter-цвета.
  static List<Color>? parseHexList(List<String>? hex) {
    if (hex == null || hex.isEmpty) return null;
    return hex.map(parseHex).toList();
  }

  static Color parseHex(String input) {
    var h = input.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    return value == null ? purple : Color(value);
  }
}
