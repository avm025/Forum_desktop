import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/media_file.dart';
import 'media_display_name.dart';
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

  /// Сначала диалог Finder/Проводник, потом копирование из локального кэша.
  /// Без предварительной загрузки — иначе окно открывается с большой задержкой.
  static Future<FileSaveResult> save(MediaFile file) async {
    if (kIsWeb) return FileSaveResult.failed;

    try {
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

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        await File(targetPath).writeAsBytes(file.bytes!, flush: true);
        return FileSaveResult.saved;
      }

      final cached = await MediaFileLoader.cachedPathIfExists(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
      if (cached != null && cached.isNotEmpty) {
        await File(cached).copy(targetPath);
        return FileSaveResult.saved;
      }

      // Fallback: докачать, если локальной копии нет.
      final source = await MediaFileLoader.resolve(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
      if (source.hasLocalPath) {
        await File(source.localPath!).copy(targetPath);
        return FileSaveResult.saved;
      }
      if (source.hasBytes) {
        await File(targetPath).writeAsBytes(source.bytes!, flush: true);
        return FileSaveResult.saved;
      }
      return FileSaveResult.failed;
    } catch (_) {
      return FileSaveResult.failed;
    }
  }

  /// Сохранение сырых байтов (например снимок карты геопозиции).
  static Future<FileSaveResult> saveBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) return FileSaveResult.failed;
    if (bytes.isEmpty) return FileSaveResult.failed;

    try {
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

  static String _fileName(MediaFile file) {
    return MediaDisplayName.forSave(file);
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
