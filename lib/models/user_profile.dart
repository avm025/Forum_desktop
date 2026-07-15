import '../api/api_config.dart';
import 'appearance_settings.dart';

/// Профиль пользователя после успешного log_in.
class UserProfile {
  final String id;
  final String name;
  final String nick;
  final String avatarUrl;
  final String about;
  final String phone;
  final AppearanceSettings appearance;

  const UserProfile({
    required this.id,
    required this.name,
    this.nick = '',
    this.avatarUrl = '',
    this.about = '',
    this.phone = '',
    this.appearance = const AppearanceSettings(),
  });

  UserProfile copyWith({
    String? name,
    String? nick,
    String? avatarUrl,
    String? about,
    String? phone,
    AppearanceSettings? appearance,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      nick: nick ?? this.nick,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      about: about ?? this.about,
      phone: phone ?? this.phone,
      appearance: appearance ?? this.appearance,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        nick: json['nick']?.toString() ?? '',
        avatarUrl: json['ava']?.toString() ?? '',
        about: json['about']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        appearance: AppearanceSettings.fromProfile(json),
      );

  /// URL для отображения (относительные пути дополняются file_server).
  String get displayAvatarUrl {
    if (avatarUrl.isEmpty) return '';
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      return avatarUrl;
    }
    return ApiConfig.resolveAssetUrl(avatarUrl);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nick': nick,
        'ava': avatarUrl,
        'about': about,
        'phone': phone,
        ...appearance.toProfilePayload(),
      };
}
