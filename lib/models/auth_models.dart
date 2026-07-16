/// Страна из `database.countries` для телефонной авторизации.
class AuthCountry {
  final String id;
  final String name;
  final String prefix;
  final String iso;
  final int length;

  const AuthCountry({
    required this.id,
    required this.name,
    required this.prefix,
    required this.iso,
    required this.length,
  });

  /// Префикс с «+» для UI и поля `sms.prefix`.
  String get prefixWithPlus {
    final p = prefix.trim();
    if (p.isEmpty) return '+';
    return p.startsWith('+') ? p : '+$p';
  }

  /// `prfxid` для SMS — id страны без «+».
  String get prfxId => id.replaceAll('+', '').trim();

  factory AuthCountry.fromJson(Map<String, dynamic> json) {
    return AuthCountry(
      id: json['id']?.toString() ?? '',
      name: json['nm']?.toString() ?? json['name']?.toString() ?? '',
      prefix: json['prefix']?.toString() ?? '',
      iso: json['iso']?.toString() ?? '',
      length: int.tryParse(json['len']?.toString() ?? '') ?? 10,
    );
  }

  static const AuthCountry russia = AuthCountry(
    id: '179',
    name: 'Россия',
    prefix: '7',
    iso: 'RU',
    length: 10,
  );

  static List<AuthCountry> listFromDatabase(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) return const [russia];
    final raw = data['countries'];
    if (raw is! List || raw.isEmpty) return const [russia];
    final list = <AuthCountry>[];
    for (final item in raw) {
      if (item is Map) {
        list.add(AuthCountry.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    list.sort((a, b) {
      if (a.iso == 'RU' && b.iso != 'RU') return -1;
      if (b.iso == 'RU' && a.iso != 'RU') return 1;
      return a.name.compareTo(b.name);
    });
    return list.isEmpty ? const [russia] : list;
  }
}

/// Результат HTTP `sms`.
class SmsRequestResult {
  final String id;
  final String? hintText;

  const SmsRequestResult({required this.id, this.hintText});
}

/// Результат HTTP `check_code`.
class CheckCodeResult {
  final bool isNew;
  final String userId;
  final String token;
  final String phone;
  final String? name;

  const CheckCodeResult({
    required this.isNew,
    required this.userId,
    required this.token,
    required this.phone,
    this.name,
  });

  factory CheckCodeResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : Map<String, dynamic>.from(json);
    return CheckCodeResult(
      isNew: map['new'] == true,
      userId: map['id']?.toString() ?? '',
      token: map['token']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      name: map['name']?.toString(),
    );
  }
}
