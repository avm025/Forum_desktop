/// Режим темы оформления (как в iOS `InterfaceStyle`).
enum AppearanceTheme {
  /// 0 — тёмная
  dark,
  /// 1 — светлая
  light,
  /// 2 — системная
  system,
}

/// Настройки оформления пользователя.
class AppearanceSettings {
  final AppearanceTheme theme;
  final int appColorId;
  final int nameColorId;
  final int avatarColorId;
  final String bgImg;
  final int textSizeOffset;
  final bool liquidGlass;
  final int transparency;

  const AppearanceSettings({
    this.theme = AppearanceTheme.system,
    this.appColorId = 1,
    this.nameColorId = 1,
    this.avatarColorId = 1,
    this.bgImg = '',
    this.textSizeOffset = 0,
    this.liquidGlass = true,
    this.transparency = 100,
  });

  static const minTextSizeOffset = -3;
  static const maxTextSizeOffset = 3;
  static const minTransparency = 0;
  static const maxTransparency = 100;

  /// Непрозрачность UI-панелей (0…1) для Liquid Glass.
  double get panelOpacity => (transparency / 100).clamp(0.0, 1.0);

  AppearanceSettings copyWith({
    AppearanceTheme? theme,
    int? appColorId,
    int? nameColorId,
    int? avatarColorId,
    String? bgImg,
    int? textSizeOffset,
    bool? liquidGlass,
    int? transparency,
  }) {
    return AppearanceSettings(
      theme: theme ?? this.theme,
      appColorId: appColorId ?? this.appColorId,
      nameColorId: nameColorId ?? this.nameColorId,
      avatarColorId: avatarColorId ?? this.avatarColorId,
      bgImg: bgImg ?? this.bgImg,
      textSizeOffset: textSizeOffset ?? this.textSizeOffset,
      liquidGlass: liquidGlass ?? this.liquidGlass,
      transparency: transparency ?? this.transparency,
    );
  }

  /// Коэффициент масштаба текста для `TextScaler`.
  double get textScaleFactor => 1.0 + textSizeOffset * 0.06;

  /// iOS: `InterfaceStyle` raw value.
  int get themeRawValue => switch (theme) {
        AppearanceTheme.dark => 0,
        AppearanceTheme.light => 1,
        AppearanceTheme.system => 2,
      };

  static AppearanceTheme themeFromRaw(int? raw) => switch (raw) {
        0 => AppearanceTheme.dark,
        1 => AppearanceTheme.light,
        _ => AppearanceTheme.system,
      };

  Map<String, dynamic> toJson() => {
        'theme': themeRawValue,
        'appColorId': appColorId,
        'nameColorId': nameColorId,
        'avatarColorId': avatarColorId,
        'bgImg': bgImg,
        'textSizeOffset': textSizeOffset,
        'liquidGlass': liquidGlass,
        'transparency': transparency,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppearanceSettings(
      theme: themeFromRaw(_int(json['theme'], 2)),
      appColorId: _int(json['appColorId'], 1),
      nameColorId: _int(json['nameColorId'], 1),
      avatarColorId: _int(json['avatarColorId'], 1),
      bgImg: json['bgImg']?.toString() ?? '',
      textSizeOffset: _int(json['textSizeOffset'], 0)
          .clamp(minTextSizeOffset, maxTextSizeOffset),
      liquidGlass: json['liquidGlass'] is bool
          ? json['liquidGlass'] as bool
          : _int(json['liquidGlass'], 1) == 1,
      transparency: _int(json['transparency'], 100)
          .clamp(minTransparency, maxTransparency),
    );
  }

  /// Поля для WS `change_profile`.
  Map<String, dynamic> toProfilePayload() => {
        'col_app_id': appColorId,
        'col_ava_id': avatarColorId,
        'col_name_id': nameColorId,
        'bg_img': bgImg,
        'theme': themeRawValue,
        'font_size': textSizeOffset,
      };

  factory AppearanceSettings.fromProfile(Map<String, dynamic> json) {
    return AppearanceSettings(
      theme: themeFromRaw(_int(json['theme'], 2)),
      appColorId: _int(json['col_app_id'], 1),
      nameColorId: _int(json['col_name_id'], 1),
      avatarColorId: _int(json['col_ava_id'], 1),
      bgImg: json['bg_img']?.toString() ?? '',
      textSizeOffset: _int(json['font_size'], 0)
          .clamp(minTextSizeOffset, maxTextSizeOffset),
    );
  }
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
