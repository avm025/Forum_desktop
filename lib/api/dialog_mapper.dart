import 'package:intl/intl.dart';

import '../api/api_config.dart';
import '../models/chat_type.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/group_additional_info_model.dart';

/// Преобразование JSON диалога с сервера в [DialogsListViewModel].
class DialogMapper {
  DialogMapper._();

  static DialogsListViewModel fromServerJson(Map<String, dynamic> json) {
    final isGrp = _parseInt(json['is_grp']) == 1;
    final avatarPath =
        (json['img_url'] ?? json['usr1_ava'] ?? '').toString();
    final colorHex = (json['color'] ?? json['usr1_color'] ?? '').toString();
    final lastMsgRaw = json['last_msg'];
    final dttmup = json['dttmup']?.toString() ?? '';

    return DialogsListViewModel(
      id: json['dlg_id']?.toString() ?? json['id']?.toString() ?? '',
      usr_id: json['usr_id']?.toString(),
      ai: _parseInt(json['ai']),
      avatar: ApiConfig.mediaUrl(avatarPath),
      avatarColor: colorHex.isNotEmpty ? ['#$colorHex'] : null,
      chatName: json['name']?.toString() ?? '',
      last_msg: lastMsgRaw?.toString() ?? '',
      last_msg_id: '',
      last_msg_fr_id: json['usr1_id']?.toString() ?? '',
      last_msg_fr_name: json['usr1_name']?.toString() ?? '',
      last_msg_dttmcr: _formatTime(dttmup),
      last_msg_status: -2,
      unread: _parseInt(json['unread']),
      chatType: isGrp ? ChatType.groupChat : ChatType.privateChat,
      isGrp: isGrp,
      pin: _parseInt(json['pin']),
      phone: json['usr1_phone']?.toString(),
      fav: _parseInt(json['fav']) == 1,
      online: _parseInt(json['online']) == 1,
      groupAditionalInfo: GroupAditionalInfoModel(
        colAvalId: _parseInt(json['col_ava_id']),
        desc: json['about']?.toString(),
        nick: json['name']?.toString(),
      ),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      if (msgDay == today) {
        return DateFormat('HH:mm').format(dt);
      }
      if (msgDay == today.subtract(const Duration(days: 1))) {
        return 'вчера';
      }
      return DateFormat('dd.MM').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
