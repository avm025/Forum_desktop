import 'package:intl/intl.dart';

import '../models/msg_read_entry.dart';

/// Тексты и форматы для пункта «просмотры» / списка `msg_read_list`.
class MsgReadDisplay {
  MsgReadDisplay._();

  /// `N просмотр` / `просмотра` / `просмотров`.
  static String viewsLabel(int count) {
    final n = count < 0 ? 0 : count;
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) {
      return '$n просмотров';
    }
    if (mod10 == 1) return '$n просмотр';
    if (mod10 >= 2 && mod10 <= 4) return '$n просмотра';
    return '$n просмотров';
  }

  /// `dd.MM.yy в HH:mm` (как iOS MessageStatusList / личка в меню).
  static String formatReadAt(String iso) {
    final raw = iso.trim();
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final date = DateFormat('dd.MM.yy').format(dt);
      final time = DateFormat('HH:mm').format(dt);
      return '$date в $time';
    } catch (_) {
      return raw;
    }
  }

  static String privateMenuLabel(List<MsgReadEntry> entries) {
    if (entries.isEmpty) return 'Нет просмотров';
    final formatted = formatReadAt(entries.first.dttmcr);
    return formatted.isNotEmpty ? formatted : 'Просмотрено';
  }
}
