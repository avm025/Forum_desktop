import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

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

  static Future<List<ApiContact>> loadContacts({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    if (kIsWeb) return const [];

    try {
      // На macOS диалог контактов блокирует UI, если запросить до появления окна.
      if (!kIsWeb && Platform.isMacOS) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }

      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) return const [];

      final raw = await FlutterContacts.getContacts(withProperties: true);
      final result = <ApiContact>[];
      final seen = <String>{};

      for (final c in raw) {
        final name = c.displayName.trim();
        for (final phone in c.phones) {
          final normalized = _normalizePhone(phone.number);
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
    } catch (_) {
      return const [];
    }
  }

  /// Оставляет только цифры, убирает ведущий «+» и прочие символы.
  static String _normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[^\d]'), '');
    // Некоторые номера приходят как 8XXXXXXXXXX — оставляем как есть.
    return digits;
  }
}
