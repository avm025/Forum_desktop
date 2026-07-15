import 'media_file.dart';
import 'message_emoji_model.dart';

/// Замена Swift `CGSize` для размеров медиа в сообщении.
class MsgSize {
  final double width;
  final double height;
  const MsgSize(this.width, this.height);

  static const MsgSize zero = MsgSize(0, 0);

  double get aspectRatio => height == 0 ? 1 : width / height;
}

/// Сообщение — порт Swift `struct MessageViewModel`.
class MessageViewModel {
  String id;
  final String type;
  final int ai;
  final bool my;
  String body;
  final String fr_name;
  final String? fr_id;
  String dttmcr;
  String dttmup;
  String dttmrd;
  String dtshow;
  int status;
  String preview;
  String url;
  String fdir;
  String text;
  final MsgSize size;
  String hash;

  // Цитируемое (родительское) сообщение — поля prn_*.
  String prn_id;
  String prn_body;
  String prn_fr_id;
  String prn_fr_name;
  String prn_type;
  String prn_fileTitle;
  MediaFile? prn_firstFile;

  /// Пересланное сообщение (`repost: 1` с сервера).
  bool repost;

  String? fileTitle;
  final String? fileSize;
  final String? fileFormat;
  String desc;

  List<MediaFile> files;
  List<int> voiceHistogram;
  bool showUserName;
  bool? avaOnTop;
  bool? avaOnBottom;
  List<MessageEmojiModel> emoji;

  double? latitude;
  double? longitude;
  String? address;

  MessageViewModel({
    required this.id,
    required this.type,
    this.ai = 0,
    this.my = false,
    this.body = '',
    this.fr_name = '',
    this.fr_id,
    this.dttmcr = '',
    this.dttmup = '',
    this.dttmrd = '',
    this.dtshow = '',
    this.status = -2,
    this.preview = '',
    this.url = '',
    this.fdir = '',
    this.text = '',
    this.size = MsgSize.zero,
    this.hash = '',
    this.prn_id = '',
    this.prn_body = '',
    this.prn_fr_id = '',
    this.prn_fr_name = '',
    this.prn_type = '',
    this.prn_fileTitle = '',
    this.prn_firstFile,
    this.repost = false,
    this.fileTitle,
    this.fileSize,
    this.fileFormat,
    this.desc = '',
    List<MediaFile>? files,
    List<int>? voiceHistogram,
    this.showUserName = false,
    this.avaOnTop,
    this.avaOnBottom,
    List<MessageEmojiModel>? emoji,
    this.latitude,
    this.longitude,
    this.address,
  })  : files = files ?? <MediaFile>[],
        voiceHistogram = voiceHistogram ?? <int>[],
        emoji = emoji ?? <MessageEmojiModel>[];

  bool get hasReply => prn_id.trim().isNotEmpty;

  /// Текст цитируемого сообщения для превью в композере и action sheet.
  String get quotedPreviewText {
    final body = this.body.trim();
    final text = this.text.trim();
    final content = body.isNotEmpty ? body : text;
    switch (type.toLowerCase()) {
      case 'voice':
        return content.isNotEmpty ? 'Аудиосообщение $content' : 'Голосовое сообщение';
      case 'file':
        if ((fileTitle ?? '').trim().isNotEmpty) {
          return 'Файл: ${fileTitle!.trim()}';
        }
        return content.isNotEmpty ? content : 'Файл';
      case 'geo':
        return content.isNotEmpty ? 'Геопозиция: $content' : 'Геопозиция';
      case 'media':
      case 'img':
      case 'image':
      case 'video':
        if (content.isNotEmpty) return content;
        return 'Медиафайлы';
      default:
        if (content.isNotEmpty) return content;
        if ((fileTitle ?? '').trim().isNotEmpty) return fileTitle!.trim();
        return '';
    }
  }

  String get quotedAuthorName => my ? 'Вы' : fr_name.trim();

  bool get quotedShowsMediaThumb {
    final mediaTypes = {'media', 'img', 'image', 'video'};
    return mediaTypes.contains(type.toLowerCase()) && files.isNotEmpty;
  }

  MediaFile? get quotedFirstFile => files.isNotEmpty ? files.first : null;

  /// Id для prn_id / прокрутки: hash у локального скелета, иначе серверный id.
  String get referenceId {
    final id = this.id.trim();
    final hash = this.hash.trim();
    if (hash.isNotEmpty && id == hash) return hash;
    if (id.isNotEmpty) return id;
    return hash;
  }

  /// Текст превью цитируемого сообщения (как AnswerMessage в iOS).
  String get replyPreviewText {
    final body = prn_body.trim();
    switch (prn_type.toLowerCase()) {
      case 'voice':
        return body.isNotEmpty ? 'Аудиосообщение $body' : 'Голосовое сообщение';
      case 'file':
        if (prn_fileTitle.trim().isNotEmpty) {
          return 'Файл: ${prn_fileTitle.trim()}';
        }
        return body.isNotEmpty ? body : 'Файл';
      case 'geo':
        return body.isNotEmpty ? 'Геопозиция: $body' : 'Геопозиция';
      case 'media':
      case 'img':
      case 'image':
      case 'video':
        if (body.isNotEmpty) return body;
        return 'Медиафайлы';
      default:
        if (body.isNotEmpty) return body;
        if (prn_fileTitle.trim().isNotEmpty) return prn_fileTitle.trim();
        return '';
    }
  }

  bool get replyShowsMediaThumb {
    final type = prn_type.toLowerCase();
    const mediaTypes = {'media', 'img', 'image', 'video'};
    return mediaTypes.contains(type) && prn_firstFile != null;
  }
  bool get hasReactions => emoji.isNotEmpty;
  bool get hasLocation => latitude != null && longitude != null;
  bool get hasFiles => files.isNotEmpty;
  bool get isVoice =>
      voiceHistogram.isNotEmpty || type == 'voice';
  bool get isImage =>
      type == 'image' ||
      type == 'media' ||
      type == 'photo' ||
      type == 'img' ||
      type == 'video';
  bool get isFile => type == 'file';
  bool get isLocation =>
      type == 'location' || type == 'geo' || hasLocation;
}
