import 'package:shared_preferences/shared_preferences.dart';

/// Локальная сессия после SMS / QR (JWT + id пользователя).
class AuthSession {
  AuthSession._();

  static const _tokenKey = 'forum_auth_token';
  static const _userIdKey = 'forum_auth_user_id';
  static const _phoneKey = 'forum_auth_phone';

  static Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  static Future<String?> loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<String?> loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  static Future<void> save({
    required String token,
    String? userId,
    String? phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token.trim());
    if (userId != null) {
      await prefs.setString(_userIdKey, userId);
    }
    if (phone != null) {
      await prefs.setString(_phoneKey, phone);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_phoneKey);
  }
}
