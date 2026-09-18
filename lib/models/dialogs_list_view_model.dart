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
  /// Id палитры градиента аватара (`usr*_col_ava_id` / `grp_col_ava_id`), как iOS.
  final int colAvaId;
  List<String>? avatarColor;
  String chatName;
  /// Доп. имена/ники для локального поиска (не для отображения).
  String searchExtra;
  String last_msg;
  String last_msg_id;
  String last_msg_fr_id;
  String last_msg_fr_name;
  String last_msg_dttmcr;
  int last_msg_status;
  int unread;
  /// `1` — непрочитанные упоминания/@all/ответы в группе ([dlg_list.tagged]).
  int tagged;
  final ChatType chatType;
  bool chatMuted;
  bool isGrp;
  String backgroundUrl;
  GroupAditionalInfoModel? groupAditionalInfo;
  int pin;
  String? phone;
  bool fav;
  bool online;

  /// Публичная группа/канал из `dlg_search`, куда ещё не вступили (`dlg_join`).
  bool awaitingJoin;

  DialogsListViewModel({
    List<MessageViewModel>? messages,
    this.usr_id,
    this.id,
    this.ai,
    this.avatar = '',
    this.colAvaId = 1,
    this.avatarColor,
    this.chatName = '',
    this.searchExtra = '',
    this.last_msg = '',
    this.last_msg_id = '',
    this.last_msg_fr_id = '',
    this.last_msg_fr_name = '',
    this.last_msg_dttmcr = '',
    this.last_msg_status = -2,
    this.unread = 0,
    this.tagged = 0,
    this.chatType = ChatType.privateChat,
    this.chatMuted = false,
    this.isGrp = false,
    this.backgroundUrl = '',
    this.groupAditionalInfo,
    this.pin = 0,
    this.phone,
    this.fav = false,
    this.online = false,
    this.awaitingJoin = false,
  }) : messages = messages ?? <MessageViewModel>[];

  bool get isPinned => pin > 0;
  bool get hasUnread => unread > 0;
  bool get hasTagged => tagged > 0;
  bool get isPublicGroup =>
      isGrp && (groupAditionalInfo?.isPublic == true);

  /// Плейсхолдер отсутствия диалога (`new_contact_dlg.md`).
  static bool isPlaceholderDlgId(String? id) {
    final s = (id ?? '').trim();
    return s.isEmpty || s == '0';
  }

  /// Зарегистрированный контакт без личного чата: `id == "0"`, есть `usr_id`.
  bool get isNewContactWithoutDialog =>
      isPlaceholderDlgId(id) &&
      (usr_id?.trim().isNotEmpty ?? false) &&
      !isGrp &&
      !fav;
}
