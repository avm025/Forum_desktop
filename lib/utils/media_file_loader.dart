import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';

/// Локальный путь или байты вложения для просмотра в чате.
class MediaFileSource {
  final String? localPath;
  final Uint8List? bytes;
  final String networkUrl;

  const MediaFileSource({
    this.localPath,
    this.bytes,
    this.networkUrl = '',
  });

  bool get hasLocalPath => localPath != null && localPath!.isNotEmpty;
  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}

/// Загрузка / кэширование файла с сервера или диска.
class MediaFileLoader {
  MediaFileLoader._();

  static Future<MediaFileSource> resolve(
    MediaFile file, {
    String? downloadUrl,
  }) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return MediaFileSource(bytes: file.bytes, networkUrl: file.url);
    }

    if (file.URL != null && file.URL!.isNotEmpty) {
      final local = File(file.URL!);
      if (await local.exists()) {
        return MediaFileSource(localPath: local.path, networkUrl: file.url);
      }
    }

    final url = (downloadUrl ?? file.url).trim();
    if (url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final cached = await _cacheRemote(file, url);
        return MediaFileSource(
          localPath: cached.path,
          networkUrl: url,
        );
      }
      if (!url.startsWith('http')) {
        final local = File(url);
        if (await local.exists()) {
          return MediaFileSource(localPath: local.path);
        }
      }
    }

    throw StateError('Не удалось получить файл ${file.fname}');
  }

  static Future<File> _cacheRemote(MediaFile file, String url) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/forum_preview');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final name = _safeName(file.fname, file.hash);
    final local = File('${dir.path}/$name');

    if (await local.exists() && await local.length() > 0) {
      return local;
    }

    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer ${ApiConfig.token}',
            'Key': ApiConfig.apiKey,
          },
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }

    await local.writeAsBytes(response.bodyBytes, flush: true);
    return local;
  }

  static String _safeName(String fname, String hash) {
    if (fname.isNotEmpty) {
      return fname.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    return 'forum_${hash.isNotEmpty ? hash : DateTime.now().millisecondsSinceEpoch}';
  }
}
