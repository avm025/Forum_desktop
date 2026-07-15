import '../api/api_config.dart';
import '../models/media_file.dart';

/// Публичный URL вложения (из `url` или `fdir` + `fname` / `title`).
class MediaFileUrl {
  MediaFileUrl._();

  static String resolve(MediaFile file) {
    final direct = file.url.trim();
    if (direct.isNotEmpty) return direct;

    final name = file.fname.trim().isNotEmpty
        ? file.fname.trim()
        : file.title.trim();
    return ApiConfig.fileUrl(file.fdir, name);
  }
}
