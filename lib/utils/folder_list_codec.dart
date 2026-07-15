/// Кодирование поля `list` для WS `dlg_grp` (dlg_id через запятую без пробелов).
class FolderListCodec {
  FolderListCodec._();

  static String encode(Iterable<String> dialogIds) {
    return dialogIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(',');
  }

  static List<String> decode(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
