/// Настройки «Уведомления и звуки» (Telegram Desktop UI + WS `device` msg_*).
///
/// Серверные флаги — per-device через `device` ([api_forum_doc] device.md).
/// Локальные — только desktop (Dock, sent sound, badge groups/channels и т.п.).
class NotificationSettings {
  /// `msg_push_on` — пуши на этом устройстве.
  final bool pushOn;

  /// Предпросмотр текста в баннере (локально) + `msg_name_on` (имена).
  final bool messagePreview;

  /// `msg_name_on` — имена в уведомлениях.
  final bool namesInNotifications;

  /// `msg_sound_on`.
  final bool soundOn;

  /// `msg_sound` — имя файла `.caf` или `''` («Нет»).
  final String soundFile;

  /// Анимация иконки в Dock (только macOS, локально).
  final bool dockBounce;

  /// Входящие звонки — локальные баннеры.
  final bool incomingCalls;

  /// Новые секретные чаты (локально; в Forum нет secret chats, для parity UI).
  final bool secretChats;

  /// Звук «отправленное сообщение» (локально).
  final bool sentMessageSound;

  /// `msg_count_on` — счётчик на иконке.
  final bool badgeEnabled;

  /// Включать группы в badge (локально).
  final bool badgeIncludeGroups;

  /// Включать каналы в badge (локально).
  final bool badgeIncludeChannels;

  /// Считать сообщения, а не чаты (локально; сервер всегда шлёт число чатов).
  final bool badgeCountMessages;

  /// `msg_new_usr_on`.
  final bool newContacts;

  /// Показывать баннеры, когда окно активно (локально).
  /// По умолчанию `true` — как Forum Desktop / AppDelegate (баннер и при фокусе).
  /// Выключить можно во вкладке «Когда приложение активно».
  final bool showWhenAppActive;

  /// `msg_pop_ups_on` — всплывающие окна пуша.
  final bool popUpsOn;

  /// `msg_vibro_on` (на desktop почти не используется, храним для синка).
  final bool vibroOn;

  const NotificationSettings({
    this.pushOn = true,
    this.messagePreview = true,
    this.namesInNotifications = true,
    this.soundOn = true,
    this.soundFile = 'sms_alert_note.caf',
    this.dockBounce = false,
    this.incomingCalls = true,
    this.secretChats = true,
    this.sentMessageSound = true,
    this.badgeEnabled = true,
    this.badgeIncludeGroups = true,
    this.badgeIncludeChannels = true,
    this.badgeCountMessages = false,
    this.newContacts = true,
    this.showWhenAppActive = true,
    this.popUpsOn = true,
    this.vibroOn = true,
  });

  static const defaults = NotificationSettings();

  /// Подпись для строки «Звук сообщений».
  String get soundDisplayName {
    if (!soundOn || soundFile.trim().isEmpty) return 'Нет';
    return MessageSoundOption.labelForFile(soundFile) ?? 'По умолчанию';
  }

  NotificationSettings copyWith({
    bool? pushOn,
    bool? messagePreview,
    bool? namesInNotifications,
    bool? soundOn,
    String? soundFile,
    bool? dockBounce,
    bool? incomingCalls,
    bool? secretChats,
    bool? sentMessageSound,
    bool? badgeEnabled,
    bool? badgeIncludeGroups,
    bool? badgeIncludeChannels,
    bool? badgeCountMessages,
    bool? newContacts,
    bool? showWhenAppActive,
    bool? popUpsOn,
    bool? vibroOn,
  }) {
    return NotificationSettings(
      pushOn: pushOn ?? this.pushOn,
      messagePreview: messagePreview ?? this.messagePreview,
      namesInNotifications: namesInNotifications ?? this.namesInNotifications,
      soundOn: soundOn ?? this.soundOn,
      soundFile: soundFile ?? this.soundFile,
      dockBounce: dockBounce ?? this.dockBounce,
      incomingCalls: incomingCalls ?? this.incomingCalls,
      secretChats: secretChats ?? this.secretChats,
      sentMessageSound: sentMessageSound ?? this.sentMessageSound,
      badgeEnabled: badgeEnabled ?? this.badgeEnabled,
      badgeIncludeGroups: badgeIncludeGroups ?? this.badgeIncludeGroups,
      badgeIncludeChannels: badgeIncludeChannels ?? this.badgeIncludeChannels,
      badgeCountMessages: badgeCountMessages ?? this.badgeCountMessages,
      newContacts: newContacts ?? this.newContacts,
      showWhenAppActive: showWhenAppActive ?? this.showWhenAppActive,
      popUpsOn: popUpsOn ?? this.popUpsOn,
      vibroOn: vibroOn ?? this.vibroOn,
    );
  }

  Map<String, dynamic> toJson() => {
        'pushOn': pushOn,
        'messagePreview': messagePreview,
        'namesInNotifications': namesInNotifications,
        'soundOn': soundOn,
        'soundFile': soundFile,
        'dockBounce': dockBounce,
        'incomingCalls': incomingCalls,
        'secretChats': secretChats,
        'sentMessageSound': sentMessageSound,
        'badgeEnabled': badgeEnabled,
        'badgeIncludeGroups': badgeIncludeGroups,
        'badgeIncludeChannels': badgeIncludeChannels,
        'badgeCountMessages': badgeCountMessages,
        'newContacts': newContacts,
        'showWhenAppActive': showWhenAppActive,
        'popUpsOn': popUpsOn,
        'vibroOn': vibroOn,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      pushOn: _bool(json['pushOn'], true),
      messagePreview: _bool(json['messagePreview'], true),
      namesInNotifications: _bool(json['namesInNotifications'], true),
      soundOn: _bool(json['soundOn'], true),
      soundFile: json['soundFile']?.toString() ?? 'sms_alert_note.caf',
      dockBounce: _bool(json['dockBounce'], false),
      incomingCalls: _bool(json['incomingCalls'], true),
      secretChats: _bool(json['secretChats'], true),
      sentMessageSound: _bool(json['sentMessageSound'], true),
      badgeEnabled: _bool(json['badgeEnabled'], true),
      badgeIncludeGroups: _bool(json['badgeIncludeGroups'], true),
      badgeIncludeChannels: _bool(json['badgeIncludeChannels'], true),
      badgeCountMessages: _bool(json['badgeCountMessages'], false),
      newContacts: _bool(json['newContacts'], true),
      showWhenAppActive: _bool(json['showWhenAppActive'], true),
      popUpsOn: _bool(json['popUpsOn'], true),
      vibroOn: _bool(json['vibroOn'], true),
    );
  }

  /// Поля для WS `device` (только msg_*).
  Map<String, dynamic> toDevicePayload() => {
        'msg_push_on': pushOn ? 1 : 0,
        'msg_sound_on': soundOn && soundFile.trim().isNotEmpty ? 1 : 0,
        'msg_vibro_on': vibroOn ? 1 : 0,
        'msg_count_on': badgeEnabled ? 1 : 0,
        'msg_name_on': namesInNotifications && messagePreview ? 1 : 0,
        'msg_new_usr_on': newContacts ? 1 : 0,
        'msg_pop_ups_on': popUpsOn ? 1 : 0,
        'msg_sound': soundOn ? soundFile.trim() : '',
      };

  /// Слияние с ответом `device_list` / серверными флагами устройства.
  NotificationSettings mergeDeviceFlags(Map<String, dynamic> json) {
    bool? flag(String key) {
      if (!json.containsKey(key)) return null;
      final v = json[key];
      if (v == null) return true; // docs: null = enabled
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().trim();
      if (s.isEmpty) return true;
      return s != '0' && s.toLowerCase() != 'false';
    }

    final sound = json['msg_sound']?.toString();
    return copyWith(
      pushOn: flag('msg_push_on'),
      soundOn: flag('msg_sound_on'),
      vibroOn: flag('msg_vibro_on'),
      badgeEnabled: flag('msg_count_on'),
      namesInNotifications: flag('msg_name_on'),
      messagePreview: flag('msg_name_on'),
      newContacts: flag('msg_new_usr_on'),
      popUpsOn: flag('msg_pop_ups_on'),
      soundFile: sound,
    );
  }

  static bool _bool(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == '1' || s == 'true') return true;
      if (s == '0' || s == 'false') return false;
    }
    return fallback;
  }
}

/// Вариант звука сообщений для пикера.
class MessageSoundOption {
  final String label;
  final String file;

  const MessageSoundOption(this.label, this.file);

  static const none = MessageSoundOption('Нет', '');

  /// Системные тоны (как в Forum_ios MessageSoundViewController + device.md).
  static const system = <MessageSoundOption>[
    none,
    MessageSoundOption('Аккорд', 'sms_alert_chord.caf'),
    MessageSoundOption('Античный', 'sms_alert_antique.caf'),
    MessageSoundOption('Аплодисменты', 'sms_alert_applause.caf'),
    MessageSoundOption('Капля', 'sms_alert_droplet.caf'),
    MessageSoundOption('Нота', 'sms_alert_note.caf'),
    MessageSoundOption('Отскок', 'sms_alert_boing.caf'),
    MessageSoundOption('Передача', 'sms_alert_handoff.caf'),
    MessageSoundOption('Переход', 'sms_alert_passage.caf'),
    MessageSoundOption('Погремушка', 'sms_alert_rattle.caf'),
    MessageSoundOption('Портал', 'sms_alert_portal.caf'),
    MessageSoundOption('Приветствие', 'sms_alert_greeting.caf'),
    MessageSoundOption('Рубеж', 'sms_alert_horizon.caf'),
    MessageSoundOption('Скольжение', 'sms_alert_slide.caf'),
  ];

  static String? labelForFile(String file) {
    final f = file.trim();
    if (f.isEmpty) return 'Нет';
    for (final o in system) {
      if (o.file == f) return o.label;
    }
    // Убрать расширение для неизвестных файлов.
    if (f.endsWith('.caf')) {
      return f.substring(0, f.length - 4);
    }
    return f;
  }
}
