import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/media_file.dart';

/// Открытие медиа/файловых вложений в системном приложении.
class FileOpener {
  FileOpener._();

  static Future<bool> open(MediaFile file) async {
    try {
      if (!kIsWeb && (file.URL?.isNotEmpty ?? false)) {
        final opened = await _openLocalPath(file.URL!);
        if (opened) return true;
      }

      if (file.url.isNotEmpty) {
        if (file.url.startsWith('http://') || file.url.startsWith('https://')) {
          return _openRemote(file);
        }
        if (!kIsWeb) {
          return _openLocalPath(file.url);
        }
        return launchUrl(Uri.parse(file.url), webOnlyWindowName: '_blank');
      }

      final bytes = file.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        return _openBytes(file, bytes);
      }
    } catch (_) {
      // Вызывающая сторона покажет сообщение об ошибке.
    }
    return false;
  }

  static Future<bool> _openLocalPath(String path) async {
    if (!kIsWeb && Platform.isMacOS) {
      try {
        final result = await Process.run('open', [path]);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    }

    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  static Future<bool> _openRemote(MediaFile file) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/forum_open');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final safeName = _safeFileName(file.fname, file.hash);
    final local = File('${dir.path}/$safeName');

    final response = await http
        .get(Uri.parse(file.url))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }

    await local.writeAsBytes(response.bodyBytes, flush: true);

    if (kIsWeb) {
      final uri = Uri.parse(
        'data:${mimeFor(file)};base64,${base64Encode(response.bodyBytes)}',
      );
      return launchUrl(uri, webOnlyWindowName: '_blank');
    }

    return _openLocalPath(local.path);
  }

  static Future<bool> _openBytes(MediaFile file, Uint8List bytes) async {
    if (kIsWeb) {
      final uri = Uri.parse(
        'data:${mimeFor(file)};base64,${base64Encode(bytes)}',
      );
      return launchUrl(uri, webOnlyWindowName: '_blank');
    }

    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/forum_open');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeName = _safeFileName(file.fname, file.hash);
    final local = File('${dir.path}/$safeName');
    await local.writeAsBytes(bytes, flush: true);
    return _openLocalPath(local.path);
  }

  static String _safeFileName(String fname, String hash) {
    if (fname.isNotEmpty) {
      return fname.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    return 'forum_${hash.isNotEmpty ? hash : DateTime.now().millisecondsSinceEpoch}';
  }

  static String mimeFor(MediaFile file) {
    switch (file.formatLabel.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'zip':
        return 'application/zip';
      default:
        return file.kind == 'image' ? 'image/*' : 'application/octet-stream';
    }
  }
}