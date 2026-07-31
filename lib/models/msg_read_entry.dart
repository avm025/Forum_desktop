import '../api/api_config.dart';

/// Запись из `msg_read_list` — кто и когда прочитал сообщение.
class MsgReadEntry {
  final String usrId;
  final String name;
  final String ava;
  final String dttmcr;
  final int? colAvaId;
  final int? colNameId;
  final String dlgId;

  const MsgReadEntry({
    required this.usrId,
    this.name = '',
    this.ava = '',
    this.dttmcr = '',
    this.colAvaId,
    this.colNameId,
    this.dlgId = '',
  });

  String get avatarUrl => ApiConfig.resolveAssetUrl(ava);

  factory MsgReadEntry.fromJson(Map<String, dynamic> json) {
    return MsgReadEntry(
      usrId: json['usr_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      ava: json['ava']?.toString() ?? '',
      dttmcr: json['dttmcr']?.toString() ?? '',
      colAvaId: _toInt(json['col_ava_id']),
      colNameId: _toInt(json['col_name_id']),
      dlgId: json['dlg_id']?.toString() ?? '',
    );
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }
}
