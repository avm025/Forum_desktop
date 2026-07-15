import '../api/api_config.dart';

/// Ответ сервера после upload (WS_MSG.md).
class UploadedFileInfo {
  final String hash;
  final String fname;
  final String fdir;
  final String kind;
  final int size;
  final String url;

  const UploadedFileInfo({
    required this.hash,
    required this.fname,
    required this.fdir,
    required this.kind,
    required this.size,
    this.url = '',
  });

  factory UploadedFileInfo.fromJson(Map<String, dynamic> json) {
    var fdir = json['fdir']?.toString() ?? '';
    if (fdir.isNotEmpty && !fdir.endsWith('/')) {
      fdir = '$fdir/';
    }
    return UploadedFileInfo(
      hash: json['hash']?.toString() ?? '',
      fname: json['fname']?.toString() ?? '',
      fdir: fdir,
      kind: json['kind']?.toString() ?? '',
      size: _parseInt(json['size']),
      url: json['url']?.toString() ?? '',
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get publicUrl {
    if (url.isNotEmpty) {
      return url.startsWith('http') ? url : ApiConfig.resolveAssetUrl(url);
    }
    return ApiConfig.fileUrl(fdir, fname);
  }

  /// Элемент массива `files` в body сообщения type=media.
  Map<String, String> toMediaFileJson({
    String width = '',
    String height = '',
    String duration = '0',
    String preview = '',
  }) {
    return {
      'kind': kind,
      'fname': fname,
      'fdir': fdir,
      'size': size.toString(),
      'width': width,
      'height': height,
      'duration': duration,
      'preview': preview,
    };
  }

  /// Элемент массива `files` в body сообщения type=file.
  Map<String, String> toDocumentFileJson({required String title}) {
    return {
      'kind': kind,
      'title': title,
      'size': size.toString(),
      'fname': fname,
      'fdir': fdir,
    };
  }
}
