import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../models/media_file.dart';
import 'file_kind.dart';
import 'media_file_loader.dart';
import 'media_file_url.dart';
import 'media_message_layout.dart';

/// Локальный маркер: свои вложения при drop обратно в чат игнорируем.
const kForumAttachmentLocalKey = 'forumAttachment';

/// DnD файлов чата ↔ Finder/Explorer (как desktop UX Forum).
class ChatFileDnd {
  ChatFileDnd._();

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Собирает [DragItem] для одного вложения.
  ///
  /// Документы — только уже локальные (без скрытой загрузки).
  /// Картинки/видео — при необходимости скачиваем в кэш, чтобы DnD работал сразу.
  static Future<DragItem?> buildDragItem(
    MediaFile file, {
    String? localId,
  }) async {
    final name = _displayName(file);
    final item = DragItem(
      suggestedName: name,
      localData: localId ?? 'forum-file-$name',
    );

    try {
      String? path;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        path = await _writeTemp(name, file.bytes!);
      } else {
        final url = MediaFileUrl.resolve(file);
        path = await MediaFileLoader.cachedPathIfExists(
          file,
          downloadUrl: url,
        );
        if ((path == null || path.isEmpty) && isMediaAttachment(file)) {
          path = await MediaFileLoader.ensureCached(
            file,
            downloadUrl: url,
          );
        }
      }

      if (path != null && path.isNotEmpty && await File(path).exists()) {
        item.add(Formats.fileUri(Uri.file(path)));
        return item;
      }
    } catch (_) {}

    return null;
  }

  /// Читает файлы из drop-сессии (группа поддерживается).
  static Future<List<MediaFile>> readDroppedFiles(DropSession session) async {
    final out = <MediaFile>[];
    for (final dropItem in session.items) {
      if (_isOwnAttachment(dropItem.localData)) continue;
      final reader = dropItem.dataReader;
      if (reader == null) continue;

      final file = await _readOne(reader);
      if (file != null) out.add(file);
      if (out.length >= MediaMessageLayout.maxFiles) break;
    }
    return out;
  }

  static bool isOwnAttachmentLocalData(Object? localData) {
    if (localData is String && localData.startsWith('forum-file-')) {
      return true;
    }
    if (localData is Map && localData[kForumAttachmentLocalKey] == true) {
      return true;
    }
    return false;
  }

  static bool _isOwnAttachment(Object? localData) =>
      isOwnAttachmentLocalData(localData);

  static Future<MediaFile?> _readOne(DataReader reader) async {
    // 1) Сначала file URI (Desktop / Finder) — без чтения PNG в heap.
    final fromUri = await _tryReadFileUri(reader);
    if (fromUri != null) return fromUri;

    // 2) Виртуальный файл (превью скрина в углу экрана) — сразу на диск, без bytes.
    final fromVirtual = await _tryReadVirtualFile(reader);
    if (fromVirtual != null) return fromVirtual;

    return null;
  }

  static Future<MediaFile?> _tryReadFileUri(DataReader reader) async {
    final completer = Completer<MediaFile?>();
    final progress = reader.getValue<Uri>(Formats.fileUri, (uri) async {
      try {
        if (uri == null) {
          completer.complete(null);
          return;
        }
        final path = uri.toFilePath();
        final f = File(path);
        if (!await f.exists()) {
          completer.complete(null);
          return;
        }
        final name = path.split(Platform.pathSeparator).last;
        final kind = FileKind.kindFromName(name);
        if (_isImageKind(kind) || FileKind.isVideoKind(kind)) {
          completer.complete(MediaFile(
            fname: name,
            title: name,
            kind: kind,
            size: await f.length(),
            URL: path,
            width: '248',
            height: '248',
          ));
          return;
        }
        final bytes = await f.readAsBytes();
        completer.complete(_mediaFromBytes(name, bytes, localPath: path));
      } catch (_) {
        completer.complete(null);
      }
    }, onError: (_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    if (progress == null) return null;
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
  }

  static Future<MediaFile?> _tryReadVirtualFile(DataReader reader) async {
    final completer = Completer<MediaFile?>();
    final progress = reader.getFile(null, (file) async {
      try {
        final name = (file.fileName?.trim().isNotEmpty == true)
            ? file.fileName!.trim()
            : ((await reader.getSuggestedName())?.trim().isNotEmpty == true
                ? (await reader.getSuggestedName())!.trim()
                : 'screenshot.png');
        final kind = FileKind.kindFromName(name);
        // Скрины из thumbnail: readAll огромный — пишем temp и не кладём bytes в MediaFile.
        final bytes = await file.readAll();
        if (bytes.isEmpty) {
          completer.complete(null);
          return;
        }
        if (_isImageKind(kind) || FileKind.isVideoKind(kind)) {
          final path = await _writeTemp(name, bytes);
          completer.complete(MediaFile(
            fname: name,
            title: name,
            kind: kind,
            size: bytes.length,
            URL: path,
            width: '248',
            height: '248',
          ));
          return;
        }
        completer.complete(_mediaFromBytes(name, bytes));
      } catch (_) {
        completer.complete(null);
      }
    }, onError: (_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    if (progress == null) return null;
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => null,
    );
  }

  static MediaFile _mediaFromBytes(
    String name,
    Uint8List bytes, {
    String? localPath,
  }) {
    final kind = FileKind.kindFromName(name);
    return MediaFile(
      fname: name,
      title: name,
      kind: kind,
      size: bytes.length,
      bytes: bytes,
      URL: localPath,
      width: FileKind.isVideoKind(kind) || _isImageKind(kind) ? '248' : '0',
      height: FileKind.isVideoKind(kind) || _isImageKind(kind) ? '248' : '0',
    );
  }

  static bool _isImageKind(String kind) {
    return const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
      'tif',
      'tiff',
    }.contains(kind);
  }

  /// Картинки/видео → media, остальное → file.
  static bool isMediaAttachment(MediaFile file) {
    final kind = file.kind.toLowerCase();
    return FileKind.isVideoKind(kind) || _isImageKind(kind);
  }

  static String _displayName(MediaFile file) {
    if (file.title.trim().isNotEmpty) return file.title.trim();
    if (file.fname.trim().isNotEmpty) return file.fname.trim();
    return 'file';
  }

  static Future<String> _writeTemp(String name, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/forum_dnd');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${folder.path}/$safe';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static FileFormat fileFormatForName(String name) {
    final ext = FileKind.extensionFromName(name);
    return switch (ext) {
      'png' => Formats.png,
      'jpg' || 'jpeg' => Formats.jpeg,
      'gif' => Formats.gif,
      'webp' => Formats.webp,
      'tif' || 'tiff' => Formats.tiff,
      'bmp' => Formats.bmp,
      'heic' => Formats.heic,
      'heif' => Formats.heif,
      'mp4' => Formats.mp4,
      'mov' => Formats.mov,
      'm4v' => Formats.m4v,
      'avi' => Formats.avi,
      'webm' => Formats.webm,
      'mkv' => Formats.mkv,
      'mp3' => Formats.mp3,
      'm4a' => Formats.m4a,
      'wav' => Formats.wav,
      'pdf' => Formats.pdf,
      'doc' => Formats.doc,
      'docx' => Formats.docx,
      'xls' => Formats.xls,
      'xlsx' => Formats.xlsx,
      'ppt' => Formats.ppt,
      'pptx' => Formats.pptx,
      'zip' => Formats.zip,
      'rar' => Formats.rar,
      '7z' => Formats.sevenZip,
      'txt' || 'log' || 'md' => Formats.plainTextFile,
      'html' || 'htm' => Formats.htmlFile,
      'json' => Formats.json,
      'csv' => Formats.csv,
      _ => const SimpleFileFormat(
          uniformTypeIdentifiers: ['public.data', 'public.item'],
          mimeTypes: ['application/octet-stream'],
        ),
    };
  }
}
