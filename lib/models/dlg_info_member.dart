import '../api/api_config.dart';

/// Участник / peer из ответа WS `dlg_info` (как iOS `GroupUsersModel`).
class DlgInfoMember {
  final String id;
  final String name;
  final String phone;
  final String nick;
  final String avatar;
  final int colAvaId;
  final bool online;
  final bool isOwner;
  final String lastSeen;
  final String? roleName;

  const DlgInfoMember({
    required this.id,
    this.name = '',
    this.phone = '',
    this.nick = '',
    this.avatar = '',
    this.colAvaId = 1,
    this.online = false,
    this.isOwner = false,
    this.lastSeen = '',
    this.roleName,
  });

  String get avatarUrl => ApiConfig.resolveAssetUrl(avatar);

  factory DlgInfoMember.fromJson(Map<String, dynamic> json) {
    final col = json['col_ava_id'] ?? json['usr_col_ava_id'];
    final colId = col is int ? col : int.tryParse('$col') ?? 1;
    return DlgInfoMember(
      id: json['usr_id']?.toString().trim() ?? '',
      name: json['name']?.toString() ??
          json['usr_name']?.toString() ??
          '',
      phone: json['phone']?.toString() ?? '',
      nick: json['nick']?.toString() ?? '',
      avatar: json['ava']?.toString() ??
          json['usr_ava']?.toString() ??
          '',
      colAvaId: colId <= 0 ? 1 : colId,
      online: json['online'] == 1 || json['online'] == true,
      isOwner: json['is_owner'] == 1 || json['is_owner'] == true,
      lastSeen: json['last_seen']?.toString() ?? '',
      roleName: json['dlg_role_name']?.toString(),
    );
  }
}

/// Разобранный ответ `dlg_info`.
class DlgInfoResult {
  final List<DlgInfoMember> users;
  final String? about;
  final String? groupNick;
  final String? groupDesc;

  const DlgInfoResult({
    this.users = const [],
    this.about,
    this.groupNick,
    this.groupDesc,
  });

  factory DlgInfoResult.fromResponse(Map<String, dynamic> resp) {
    final usersRaw = resp['users'];
    final users = <DlgInfoMember>[];
    if (usersRaw is List) {
      for (final item in usersRaw) {
        if (item is! Map) continue;
        final m = DlgInfoMember.fromJson(Map<String, dynamic>.from(item));
        if (m.id.isNotEmpty) users.add(m);
      }
    }

    final data = resp['data'];
    Map<String, dynamic>? dataMap;
    if (data is Map) {
      dataMap = Map<String, dynamic>.from(data);
    }

    return DlgInfoResult(
      users: users,
      about: resp['about']?.toString() ??
          dataMap?['about']?.toString(),
      groupNick: resp['nick']?.toString() ??
          dataMap?['nick']?.toString(),
      groupDesc: resp['desc']?.toString() ??
          dataMap?['desc']?.toString() ??
          resp['description']?.toString(),
    );
  }
}
