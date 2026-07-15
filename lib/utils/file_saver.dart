import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/media_file.dart';
import 'media_file_loader.dart';
import 'media_file_url.dart';

/// Результат сохранения файла.
enum FileSaveResult {
  saved,
  cancelled,
  failed,
}

/// Сохранение вложения на диск (диалог «Сохранить как…»).
class FileSaver {
  FileSaver._();

  static Future<FileSaveResult> save(MediaFile file) async {
    if (kIsWeb) return FileSaveResult.failed;

    try {
      final downloadUrl = MediaFileUrl.resolve(file);
      if (downloadUrl.isEmpty) return FileSaveResult.failed;

      final source = await MediaFileLoader.resolve(
        file,
        downloadUrl: downloadUrl,
      );
      final bytes = await _readBytes(source);
      if (bytes == null || bytes.isEmpty) return FileSaveResult.failed;

      final fileName = _fileName(file);
      final pickedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить файл',
        fileName: fileName,
        type: FileType.any,
      );
      if (pickedPath == null || pickedPath.trim().isEmpty) {
        return FileSaveResult.cancelled;
      }

      final targetPath = _normalizeSavePath(pickedPath.trim(), fileName);
      await File(targetPath).writeAsBytes(bytes, flush: true);
      return FileSaveResult.saved;
    } catch (_) {
      return FileSaveResult.failed;
    }
  }

  static Future<Uint8List?> _readBytes(MediaFileSource source) async {
    if (source.hasBytes) return source.bytes;
    if (source.hasLocalPath) {
      return File(source.localPath!).readAsBytes();
    }
    return null;
  }

  static String _fileName(MediaFile file) {
    if (file.title.trim().isNotEmpty) {
      return file.title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    if (file.fname.trim().isNotEmpty) {
      return file.fname.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    return 'document';
  }

  /// macOS иногда возвращает путь без расширения — дописываем из имени файла.
  static String _normalizeSavePath(String pickedPath, String fileName) {
    final pickedExt = _extension(pickedPath);
    final nameExt = _extension(fileName);
    if (pickedExt.isNotEmpty || nameExt.isEmpty) return pickedPath;
    return '$pickedPath.$nameExt';
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }
}
