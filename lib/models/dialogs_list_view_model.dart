import 'chat_type.dart';
import 'group_additional_info_model.dart';
import 'message_view_model.dart';

/// Диалог в списке — порт Swift `struct DialogsListViewModel`.
class DialogsListViewModel {
  List<MessageViewModel> messages;
  String? usr_id;
  String? id;
  final int? ai;
  final String avatar;
  List<String>? avatarColor;
  String chatName;
  String last_msg;
  String last_msg_id;
  String last_msg_fr_id;
  String last_msg_fr_name;
  String last_msg_dttmcr;
  int last_msg_status;
  int unread;
  final ChatType chatType;
  bool chatMuted;
  bool isGrp;
  String backgroundUrl;
  GroupAditionalInfoModel? groupAditionalInfo;
  int pin;
  String? phone;
  bool fav;
  bool online;

  DialogsListViewModel({
    List<MessageViewModel>? messages,
    this.usr_id,
    this.id,
    this.ai,
    this.avatar = '',
    this.avatarColor,
    this.chatName = '',
    this.last_msg = '',
    this.last_msg_id = '',
    this.last_msg_fr_id = '',
    this.last_msg_fr_name = '',
    this.last_msg_dttmcr = '',
    this.last_msg_status = -2,
    this.unread = 0,
    this.chatType = ChatType.privateChat,
    this.chatMuted = false,
    this.isGrp = false,
    this.backgroundUrl = '',
    this.groupAditionalInfo,
    this.pin = 0,
    this.phone,
    this.fav = false,
    this.online = false,
  }) : messages = messages ?? <MessageViewModel>[];

  bool get isPinned => pin > 0;
  bool get hasUnread => unread > 0;
}
