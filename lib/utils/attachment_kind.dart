import '../models/media_file.dart';

/// Тип вложения для выбора просмотрщика в чате.
enum AttachmentViewKind { image, video, pdf, text, other }

class AttachmentKind {
  AttachmentKind._();

  static AttachmentViewKind of(MediaFile file) {
    if (file.isVideo) return AttachmentViewKind.video;
    if (_isPdf(file)) return AttachmentViewKind.pdf;
    if (_isText(file)) return AttachmentViewKind.text;
    if (_isImage(file)) return AttachmentViewKind.image;
    return AttachmentViewKind.other;
  }

  static bool _isImage(MediaFile file) {
    const exts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'};
    final ext = file.formatLabel.toLowerCase();
    final kind = file.kind.toLowerCase();
    return exts.contains(ext) || exts.contains(kind);
  }

  static bool _isPdf(MediaFile file) {
    final ext = file.formatLabel.toLowerCase();
    return ext == 'pdf' || file.kind.toLowerCase() == 'pdf';
  }

  static bool _isText(MediaFile file) {
    const exts = {'txt', 'json', 'xml', 'csv', 'md', 'log'};
    return exts.contains(file.formatLabel.toLowerCase());
  }
}
