/// Дополнительная информация о групповом диалоге —
/// порт Swift `struct GroupAditionalInfoModel`.
class GroupAditionalInfoModel {
  int? colAvalId;
  String? desc;
  String? nick;
  bool? isPublic;
  String? words;
  bool? showRoles;
  String? bgImg;

  GroupAditionalInfoModel({
    this.colAvalId,
    this.desc,
    this.nick,
    this.isPublic,
    this.words,
    this.showRoles,
    this.bgImg,
  });

  factory GroupAditionalInfoModel.fromJson(Map<String, dynamic> json) =>
      GroupAditionalInfoModel(
        colAvalId: json['colAvalId'] as int?,
        desc: json['desc'] as String?,
        nick: json['nick'] as String?,
        isPublic: json['isPublic'] as bool?,
        words: json['words'] as String?,
        showRoles: json['showRoles'] as bool?,
        bgImg: json['bgImg'] as String?,
      );
}
