/// Сеанс устройства из WS `device_list` (как DeviceSessionModel в Forum_ios).
class DeviceSession {
  final String uid;
  final String os;
  final String osVer;
  final String model;
  final String app;
  final String address;
  final String? dttmup;
  final String? dttmcr;
  final bool online;

  const DeviceSession({
    required this.uid,
    this.os = '',
    this.osVer = '',
    this.model = '',
    this.app = '',
    this.address = '',
    this.dttmup,
    this.dttmcr,
    this.online = false,
  });

  static DeviceSession? fromJson(Map<String, dynamic> json) {
    final uid = json['uid']?.toString() ?? '';
    if (uid.isEmpty) return null;
    return DeviceSession(
      uid: uid,
      os: json['os']?.toString() ?? '',
      osVer: json['os_ver']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      app: json['app']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      dttmup: json['dttmup']?.toString(),
      dttmcr: json['dttmcr']?.toString(),
      online: json['online'] == true,
    );
  }

  String get titleText {
    final trimmed = model.trim();
    return trimmed.isEmpty ? os : trimmed;
  }

  /// «Forum 1.2.3, iOS 18.2»
  String get subtitleText {
    final parts = <String>[];
    final appTrimmed = app.trim();
    if (appTrimmed.isNotEmpty) parts.add('Forum $appTrimmed');
    final osTrimmed = os.trim();
    final verTrimmed = osVer.trim();
    if (osTrimmed.isNotEmpty) {
      parts.add(verTrimmed.isEmpty ? osTrimmed : '$osTrimmed $verTrimmed');
    }
    return parts.join(', ');
  }

  String get locationText => address.trim();

  /// «онлайн» / время последней активности (как в iOS).
  String get trailingStatusText {
    if (online) return 'онлайн';
    return _relativeActiveText(dttmup ?? dttmcr);
  }

  static String _relativeActiveText(String? raw) {
    final date = _parseServerDate(raw);
    if (date == null) return '';
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(day).inDays;

    String two(int v) => v.toString().padLeft(2, '0');
    if (diffDays == 0) return '${two(local.hour)}:${two(local.minute)}';
    if (diffDays == 1) return 'вчера';
    if (diffDays < 7) {
      const week = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      return week[local.weekday - 1];
    }
    final yy = (local.year % 100).toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.$yy';
  }

  static DateTime? _parseServerDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }
}
