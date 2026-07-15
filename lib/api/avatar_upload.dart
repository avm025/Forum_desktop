import '../api/uploaded_file_info.dart';

/// Путь `ava` для WS `change_profile` после upload.
String avatarPathFromUpload(UploadedFileInfo uploaded) {
  final url = uploaded.url.trim();
  if (url.isNotEmpty) return url;
  final dir = uploaded.fdir.trim();
  final name = uploaded.fname.trim();
  if (dir.isEmpty) return name;
  return dir.endsWith('/') ? '$dir$name' : '$dir/$name';
}
