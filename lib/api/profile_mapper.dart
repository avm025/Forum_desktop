import 'dart:convert';

/// Разбор ответа WS `change_profile`.
Map<String, dynamic>? parseChangeProfileUser(Map<String, dynamic> resp) {
  if (resp['success'] != true) return null;

  final data = resp['data'];
  List<dynamic>? list;
  if (data is String) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) list = decoded;
    } catch (_) {
      return null;
    }
  } else if (data is List) {
    list = data;
  }

  if (list == null || list.isEmpty) return null;
  final first = list.first;
  if (first is Map) return Map<String, dynamic>.from(first);
  return null;
}

/// Объединяет локальные настройки с полями профиля с сервера.
Map<String, dynamic> mergeProfileAppearance(
  Map<String, dynamic> profile,
  Map<String, dynamic> payload,
) {
  final merged = {...profile, ...payload};

  final payloadAva = payload['ava']?.toString() ?? '';
  final profileAva = profile['ava']?.toString() ?? '';
  if (payload.containsKey('ava') &&
      payloadAva.isEmpty &&
      profileAva.isNotEmpty) {
    merged['ava'] = profileAva;
  }

  return merged;
}
