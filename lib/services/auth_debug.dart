/// Отладочная авторизация по SMS: постоянный код = последние 5 цифр номера.
///
/// Сервер в `test: true` всё равно генерирует свой код в `text`.
/// Если пользователь вводит суффикс номера, на `check_code` подставляется
/// код из ответа `sms` — вход работает без реальной SMS.
class AuthDebug {
  AuthDebug._();

  /// Включить отладочный SMS-код. Для боя — `false`.
  static const bool enabled = true;

  static bool get useTestSms => enabled;

  /// Постоянный код для отладки: последние 5 цифр телефона.
  static String codeFromPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '00000';
    if (digits.length <= 5) return digits.padLeft(5, '0');
    return digits.substring(digits.length - 5);
  }

  static String? parseServerCode(String? hintText) {
    if (hintText == null || hintText.isEmpty) return null;
    final match = RegExp(r'\d{5}').firstMatch(hintText);
    return match?.group(0);
  }

  static String hintForPhone(String phone) {
    final code = codeFromPhone(phone);
    return 'Отладка: код = последние 5 цифр номера ($code)';
  }

  /// Что отправить в `check_code`.
  static String resolveCheckCode({
    required String entered,
    required String phone,
    String? serverCodeFromHint,
  }) {
    if (!enabled) return entered;
    if (entered == codeFromPhone(phone) &&
        serverCodeFromHint != null &&
        serverCodeFromHint.length == 5) {
      return serverCodeFromHint;
    }
    return entered;
  }
}
