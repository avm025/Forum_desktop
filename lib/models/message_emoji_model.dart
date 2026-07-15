/// Реакция-эмодзи на сообщение — порт Swift `struct MessageEmojiModel`.
class MessageEmojiModel {
  String emoji;
  bool my;
  int qty;
  List<String> usrName;
  List<String> usrIds;
  List<int> avaColor;
  List<String> avatars;
  List<String> date;

  MessageEmojiModel({
    required this.emoji,
    this.my = false,
    this.qty = 0,
    this.usrName = const [],
    this.usrIds = const [],
    this.avaColor = const [],
    this.avatars = const [],
    this.date = const [],
  });

  factory MessageEmojiModel.fromJson(Map<String, dynamic> json) =>
      MessageEmojiModel(
        emoji: json['emoji'] as String? ?? '',
        my: json['my'] as bool? ?? false,
        qty: json['qty'] as int? ?? 0,
        usrName: (json['usrName'] as List?)?.cast<String>() ?? const [],
        usrIds: (json['usrIds'] as List?)?.cast<String>() ?? const [],
        avaColor: (json['avaColor'] as List?)?.cast<int>() ?? const [],
        avatars: (json['avatars'] as List?)?.cast<String>() ?? const [],
        date: (json['date'] as List?)?.cast<String>() ?? const [],
      );
}
