/// Папка (группа) диалогов — ответ dlg_grp_list.
class DialogGroup {
  final String id;
  final String name;
  final String list;
  final int sort;

  const DialogGroup({
    required this.id,
    required this.name,
    this.list = '',
    this.sort = 0,
  });

  factory DialogGroup.fromJson(Map<String, dynamic> json) => DialogGroup(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        list: json['list']?.toString() ?? '',
        sort: _parseInt(json['sort']),
      );

  /// ID диалогов в папке (поле list — через запятую).
  Set<String> get dialogIds {
    if (list.trim().isEmpty) return const {};
    return list
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }
}

int _parseInt(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
