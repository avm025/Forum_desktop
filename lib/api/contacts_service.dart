import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../utils/utf16.dart';

/// Контакт для запроса dlg_list.
class ApiContact {
  final String phone;
  final String name;

  const ApiContact({required this.phone, required this.name});

  Map<String, String> toJson() => {'phone': phone, 'name': name};
}

/// Чтение контактов ОС и нормализация телефонов (без «+»).
class ContactsService {
  ContactsService._();

  static List<ApiContact>? _cache;

  /// Уже загруженные контакты (без повторного запроса к ОС).
  static List<ApiContact> get cached =>
      List<ApiContact>.unmodifiable(_cache ?? const []);

  static Future<List<ApiContact>> loadContacts({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    if (kIsWeb) return const [];
    // flutter_contacts на Windows часто без реализации / зависает на permission.
    if (Platform.isWindows) return const [];

    try {
      return await _loadContactsInner().timeout(
        const Duration(seconds: 4),
        onTimeout: () => const [],
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ApiContact>> _loadContactsInner() async {
    // На macOS диалог контактов блокирует UI, если запросить до появления окна.
    if (!kIsWeb && Platform.isMacOS) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) return const [];

    final raw = await FlutterContacts.getContacts(withProperties: true);
    final result = <ApiContact>[];
    final seen = <String>{};

    for (final c in raw) {
      final name = sanitizeUtf16(c.displayName.trim());
      for (final phone in c.phones) {
        final normalized = normalizePhone(phone.number);
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        result.add(ApiContact(
          phone: normalized,
          name: name.isNotEmpty ? name : normalized,
        ));
      }
    }
    _cache = result;
    return result;
  }

  /// Оставляет только цифры, убирает ведущий «+» и прочие символы.
  static String normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[^\d]'), '');
    // Некоторые номера приходят как 8XXXXXXXXXX — оставляем как есть.
    return digits;
  }

  /// Имя из телефонной книги по номеру (как iOS `GL.phonesArr`).
  static String? displayNameForPhone(
    List<ApiContact> contacts,
    String? phone,
  ) {
    final digits = normalizePhone(phone ?? '');
    if (digits.length < 7 || contacts.isEmpty) return null;

    String? best;
    var bestLen = 0;
    for (final c in contacts) {
      final cp = c.phone;
      if (cp.length < 7) continue;
      final match = cp == digits ||
          (cp.length >= 10 && digits.endsWith(cp)) ||
          (digits.length >= 10 && cp.endsWith(digits));
      if (!match) continue;
      if (cp.length > bestLen) {
        bestLen = cp.length;
        best = c.name.trim();
      }
    }
    if (best == null || best.isEmpty) return null;
    return best;
  }
}
