import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Файл в сообщении — порт Swift `struct MediaFile`.
class MediaFile {
  String hash;
  String url;
  String fname;
  String fdir;
  String kind;
  String preview;
  String title;
  int size;
  String width;
  String height;
  int duration;
  bool uploaded;

  /// Swift `URL?` -> локальный путь/ссылка в виде строки.
  String? URL;

  /// Байты выбранного локально файла (для предпросмотра без загрузки на сервер).
  /// Не входит в исходную Swift-модель и не сериализуется.
  Uint8List? bytes;

  MediaFile({
    this.hash = '',
    this.url = '',
    this.fname = '',
    this.fdir = '',
    this.kind = '',
    this.preview = '',
    this.title = '',
    this.size = 0,
    this.width = '0',
    this.height = '0',
    this.duration = 0,
    this.uploaded = false,
    this.URL,
    this.bytes,
  });

  double get widthValue => double.tryParse(width) ?? 0;
  double get heightValue => double.tryParse(height) ?? 0;

  /// Видео: kind/расширение (в т.ч. серверный `video`).
  /// Голосовые (m4a/mp3) с duration > 0 — НЕ видео.
  bool get isVideo {
    final k = kind.trim().toLowerCase();
    final ext = formatLabel.toLowerCase();
    if (_audioExts.contains(k) || _audioExts.contains(ext)) return false;
    if (k == 'video' || _videoExts.contains(k)) return true;
    if (_videoExts.contains(ext)) return true;
    // duration>0 у jpg/png не считаем видео (бывает мусор в payload).
    if (duration > 0 && !_imageExts.contains(k) && !_imageExts.contains(ext)) {
      return true;
    }
    return false;
  }

  bool get isAudio {
    final k = kind.trim().toLowerCase();
    final ext = formatLabel.toLowerCase();
    return _audioExts.contains(k) || _audioExts.contains(ext);
  }

  static const _audioExts = {
    'm4a',
    'mp3',
    'aac',
    'wav',
    'opus',
    'flac',
    'ogg',
    'voice',
  };

  static const _videoExts = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
  };

  static const _imageExts = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
    'img',
    'image',
  };

  /// Размер превью в чате с сохранением пропорций (без обрезки).
  Size chatDisplaySize({double maxWidth = 280, double maxHeight = 420}) {
    var w = widthValue;
    var h = heightValue;
    if (w <= 0 || h <= 0) {
      return Size(maxWidth, maxWidth * 0.75);
    }
    final scale = math.min(1.0, math.min(maxWidth / w, maxHeight / h));
    return Size(w * scale, h * scale);
  }

  /// Расширение файла в верхнем регистре, напр. "PDF".
  String get formatLabel {
    final dot = fname.lastIndexOf('.');
    if (dot < 0 || dot == fname.length - 1) return '';
    return fname.substring(dot + 1).toUpperCase();
  }

  /// Человекочитаемый размер: "1,2 МБ", "340 КБ" и т.д.
  String get humanSize {
    if (size <= 0) return '';
    const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    var value = size.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final str = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$str ${units[unit]}';
  }

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        hash: json['hash'] as String? ?? '',
        url: json['url'] as String? ?? '',
        fname: json['fname'] as String? ?? '',
        fdir: json['fdir'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
        title: json['title'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        width: json['width']?.toString() ?? '0',
        height: json['height']?.toString() ?? '0',
        duration: json['duration'] as int? ?? 0,
        uploaded: json['uploaded'] as bool? ?? false,
        URL: json['URL'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'url': url,
        'fname': fname,
        'fdir': fdir,
        'kind': kind,
        'preview': preview,
        'title': title,
        'size': size,
        'width': width,
        'height': height,
        'duration': duration,
        'uploaded': uploaded,
        'URL': URL,
      };
}
