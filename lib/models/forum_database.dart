/// Палитра градиента аватара (`database.ava_col`).
class AvatarColorPalette {
  final int id;
  final String l1;
  final String l2;
  final String d1;
  final String d2;

  const AvatarColorPalette({
    required this.id,
    required this.l1,
    required this.l2,
    required this.d1,
    required this.d2,
  });

  factory AvatarColorPalette.fromJson(Map<String, dynamic> json) {
    return AvatarColorPalette(
      id: _int(json['id'], 1),
      l1: json['l1']?.toString() ?? '904FFF',
      l2: json['l2']?.toString() ?? '6642F4',
      d1: json['d1']?.toString() ?? '904FFF',
      d2: json['d2']?.toString() ?? '6642F4',
    );
  }

  List<String> hexForDark(bool isDark) =>
      isDark ? [d1, d2] : [l1, l2];
}

/// Цвета приложения (`database.app_col`).
class AppColorPalette {
  final int id;
  final String l1;
  final String l2;
  final String d1;
  final String d2;

  const AppColorPalette({
    required this.id,
    required this.l1,
    required this.l2,
    required this.d1,
    required this.d2,
  });

  factory AppColorPalette.fromJson(Map<String, dynamic> json) {
    return AppColorPalette(
      id: _int(json['id'], 1),
      l1: json['l1']?.toString() ?? '6642F4',
      l2: json['l2']?.toString() ?? '42CE00',
      d1: json['d1']?.toString() ?? '904FFF',
      d2: json['d2']?.toString() ?? '9BFF4B',
    );
  }
}

/// Цвет имени в чатах (`database.name_col`).
class NameColorPalette {
  final int id;
  final String l;
  final String d;
  final double lAlpha;
  final double dAlpha;

  const NameColorPalette({
    required this.id,
    required this.l,
    required this.d,
    this.lAlpha = 1,
    this.dAlpha = 1,
  });

  factory NameColorPalette.fromJson(Map<String, dynamic> json) {
    return NameColorPalette(
      id: _int(json['id'], 1),
      l: json['l']?.toString() ?? '8D58FF',
      d: json['d']?.toString() ?? '8D58FF',
      lAlpha: _double(json['l_a'], 1),
      dAlpha: _double(json['d_a'], 1),
    );
  }
}

/// Фон чата (`database.bg`).
class ChatBackgroundOption {
  final int id;
  final String url;
  final bool dark;

  const ChatBackgroundOption({
    required this.id,
    required this.url,
    required this.dark,
  });

  bool get isEmpty => url.trim().isEmpty;

  factory ChatBackgroundOption.empty({required bool dark}) => ChatBackgroundOption(
        id: 0,
        url: '',
        dark: dark,
      );

  factory ChatBackgroundOption.fromJson(Map<String, dynamic> json) {
    return ChatBackgroundOption(
      id: _int(json['id'], 0),
      url: json['url']?.toString() ?? '',
      dark: _int(json['dark'], 0) == 1,
    );
  }
}

/// Справочники оформления из HTTP `database`.
class ForumDatabase {
  final List<AvatarColorPalette> avatarColors;
  final List<AppColorPalette> appColors;
  final List<NameColorPalette> nameColors;
  final List<ChatBackgroundOption> lightBackgrounds;
  final List<ChatBackgroundOption> darkBackgrounds;

  const ForumDatabase({
    required this.avatarColors,
    required this.appColors,
    required this.nameColors,
    required this.lightBackgrounds,
    required this.darkBackgrounds,
  });

  factory ForumDatabase.fromResponse(Map<String, dynamic> data) {
    final ava = _list(data['ava_col'])
        .map((e) => AvatarColorPalette.fromJson(e))
        .toList();
    final app = _list(data['app_col'])
        .map((e) => AppColorPalette.fromJson(e))
        .toList();
    final names = _list(data['name_col'])
        .map((e) => NameColorPalette.fromJson(e))
        .toList();

    final lightBgs = <ChatBackgroundOption>[
      ChatBackgroundOption.empty(dark: false),
    ];
    final darkBgs = <ChatBackgroundOption>[
      ChatBackgroundOption.empty(dark: true),
    ];

    for (final raw in _list(data['bg'])) {
      final bg = ChatBackgroundOption.fromJson(raw);
      if (bg.dark) {
        darkBgs.add(bg);
      } else {
        lightBgs.add(bg);
      }
    }

    return ForumDatabase(
      avatarColors: ava.isEmpty ? defaults().avatarColors : ava,
      appColors: app.isEmpty ? defaults().appColors : app,
      nameColors: names.isEmpty ? defaults().nameColors : names,
      lightBackgrounds: lightBgs,
      darkBackgrounds: darkBgs,
    );
  }

  static ForumDatabase defaults() {
    return ForumDatabase(
      avatarColors: const [
        AvatarColorPalette(id: 1, l1: '904FFF', l2: '5B36C9', d1: '904FFF', d2: '5B36C9'),
        AvatarColorPalette(id: 2, l1: '3B82F6', l2: '22D3EE', d1: '3B82F6', d2: '22D3EE'),
        AvatarColorPalette(id: 3, l1: 'FF7A45', l2: 'FF4D4F', d1: 'FF7A45', d2: 'FF4D4F'),
        AvatarColorPalette(id: 4, l1: '22C55E', l2: '14B8A6', d1: '22C55E', d2: '14B8A6'),
        AvatarColorPalette(id: 5, l1: 'EC4899', l2: 'F43F5E', d1: 'EC4899', d2: 'F43F5E'),
        AvatarColorPalette(id: 6, l1: 'F59E0B', l2: 'EF4444', d1: 'F59E0B', d2: 'EF4444'),
      ],
      appColors: const [
        AppColorPalette(id: 1, l1: '6642F4', l2: '42CE00', d1: '904FFF', d2: '9BFF4B'),
        AppColorPalette(id: 2, l1: '14B8A6', l2: '22D3EE', d1: '2DD4BF', d2: '67E8F9'),
        AppColorPalette(id: 3, l1: '22C55E', l2: '84CC16', d1: '4ADE80', d2: 'A3E635'),
        AppColorPalette(id: 4, l1: 'F97316', l2: 'FACC15', d1: 'FB923C', d2: 'FDE047'),
        AppColorPalette(id: 5, l1: '3B82F6', l2: '6366F1', d1: '60A5FA', d2: '818CF8'),
      ],
      nameColors: const [
        NameColorPalette(id: 1, l: '8D58FF', d: '8D58FF'),
        NameColorPalette(id: 2, l: 'EC4899', d: 'F472B6'),
        NameColorPalette(id: 3, l: 'EF4444', d: 'F87171'),
        NameColorPalette(id: 4, l: 'F97316', d: 'FB923C'),
        NameColorPalette(id: 5, l: 'EAB308', d: 'FACC15'),
      ],
      lightBackgrounds: [ChatBackgroundOption.empty(dark: false)],
      darkBackgrounds: [ChatBackgroundOption.empty(dark: true)],
    );
  }

  AvatarColorPalette? avatarById(int id) =>
      avatarColors.where((e) => e.id == id).firstOrNull;

  AppColorPalette? appColorById(int id) =>
      appColors.where((e) => e.id == id).firstOrNull;

  NameColorPalette? nameColorById(int id) =>
      nameColors.where((e) => e.id == id).firstOrNull;

  List<ChatBackgroundOption> backgroundsFor(bool isDark) =>
      isDark ? darkBackgrounds : lightBackgrounds;

  ChatBackgroundOption? backgroundByUrl(String url, {required bool isDark}) {
    final normalized = url.trim();
    for (final bg in backgroundsFor(isDark)) {
      if (bg.url.trim() == normalized) return bg;
    }
    return null;
  }
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _double(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
