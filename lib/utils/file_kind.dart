/// Расширение и kind для upload / msg body (WS_MSG.md).
class FileKind {
  FileKind._();

  static String extensionFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String kindFromName(String name) {
    final ext = extensionFromName(name);
    return switch (ext) {
      'jpeg' => 'jpg',
      'mpeg' => 'mp3',
      '' => 'bin',
      _ => ext,
    };
  }

  /// kind для upload type=media (WS_MSG_MEDIA.md: jpg, mp4).
  static String mediaKindFromName(String name) {
    final kind = kindFromName(name);
    if (isVideoKind(kind)) return 'mp4';
    if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'}.contains(kind)) {
      return 'jpg';
    }
    return kind;
  }

  static bool isVideoKind(String kind) {
    return const {'mp4', 'mov', 'avi', 'mkv', 'webm', 'ogg'}.contains(kind);
  }

  static bool isImageKind(String kind) {
    return const {
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
    }.contains(kind.toLowerCase());
  }

  static bool isImageName(String name) => isImageKind(kindFromName(name));

  static String fnameForHash(String hash, String originalName) {
    final ext = extensionFromName(originalName);
    if (ext.isEmpty) return hash;
    return '$hash.$ext';
  }
}
