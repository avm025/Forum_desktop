import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Персистентный uid приложения для автологина.
class DeviceIdService {
  DeviceIdService._();

  static const _key = 'forum_app_uid';
  static const _uuid = Uuid();

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final uid = _uuid.v4().toUpperCase();
    await prefs.setString(_key, uid);
    return uid;
  }
}
