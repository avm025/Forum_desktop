import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../utils/file_kind.dart';
import 'inline_video_preview.dart';

/// Превью медиа в сообщении.
///
/// Локальные скрины (Shift-⌘-4) показываем через нативный [Image.file] +
/// [cacheWidth]/[cacheHeight] — без package:image (он вешает UI на Retina PNG).
/// Видео (в т.ч. видеосообщения) — первый кадр через [MediaThumbCache].
class MediaThumbTile extends StatefulWidget {
  final MediaFile file;
  final double width;
  final double height;
  final BoxFit fit;
  /// Без градиента/иконки/спиннера, пока файл не готов.
  final bool blankWhileLoading;

  const MediaThumbTile({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.blankWhileLoading = false,
  });

  @override
  State<MediaThumbTile> createState() => _MediaThumbTileState();
}

class _MediaThumbTileState extends State<MediaThumbTile> {
  File? _cachedFile;
  bool _loading = false;
  bool _error = false;

  bool get _isVideo =>
      widget.file.isVideo || FileKind.isVideoKind(widget.file.kind);

  /// Локальный JPEG-кадр, если уже положили в [MediaFile.preview].
  File? get _localPreviewFile {
    final p = widget.file.preview.trim();
    if (p.isEmpty || p.startsWith('http')) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  @override
  void initState() {
    super.initState();
    _cachedFile = _localPreviewFile ?? MediaThumbCache.peekSync(widget.file);
    if (_isVideo) {
      _loading = _cachedFile == null;
      _loadVideoThumb();
      return;
    }
    // До первого кадра: если кэша нет — сразу blank, без градиента/иконки.
    if (_cachedFile == null && _needsAsyncLoad) {
      _loading = true;
    }
    _load();
  }

  bool get _needsAsyncLoad {
    if (_isVideo) return true;
    final localPath = widget.file.URL?.trim() ?? '';
    final hasLocal = localPath.isNotEmpty &&
        !localPath.startsWith('http') &&
        File(localPath).existsSync();
    final smallBytes = widget.file.bytes != null &&
        widget.file.bytes!.isNotEmpty &&
        widget.file.bytes!.length < 2 * 1024 * 1024;
    if (hasLocal || smallBytes) return false;
    return MediaThumbCache.needsRemoteThumbnail(widget.file);
  }

  @override
  void didUpdateWidget(covariant MediaThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sizeChanged = (oldWidget.width - widget.width).abs() > 0.5 ||
        (oldWidget.height - widget.height).abs() > 0.5;
    if (oldWidget.file.hash != widget.file.hash ||
        oldWidget.file.url != widget.file.url ||
        oldWidget.file.URL != widget.file.URL ||
        oldWidget.file.bytes != widget.file.bytes ||
        oldWidget.file.kind != widget.file.kind) {
      final sameLocal = _sameLocalUrl(oldWidget.file, widget.file);
      final peeked =
          _localPreviewFile ?? MediaThumbCache.peekSync(widget.file);
      if (peeked != null) {
        _cachedFile = peeked;
        _loading = false;
        _error = false;
      } else if (sameLocal && _cachedFile != null) {
        // Upload добавил hash — оставляем уже показанный кадр.
        MediaThumbCache.alias(oldWidget.file, widget.file);
        _loading = false;
        _error = false;
      } else {
        _cachedFile = null;
        _error = false;
        _loading = _isVideo || _needsAsyncLoad;
      }
      if (_isVideo) {
        _loadVideoThumb();
      } else {
        _load();
      }
    } else if (sizeChanged && mounted) {
      setState(() {});
    }
  }

  static bool _sameLocalUrl(MediaFile a, MediaFile b) {
    final pa = a.URL?.trim() ?? '';
    final pb = b.URL?.trim() ?? '';
    return pa.isNotEmpty && !pa.startsWith('http') && pa == pb;
  }

  Future<void> _loadVideoThumb() async {
    if (_cachedFile != null) {
      try {
        final file = await MediaThumbCache.ensureThumbnail(widget.file);
        if (mounted && _cachedFile?.path != file.path) {
          setState(() => _cachedFile = file);
        }
      } catch (_) {}
      return;
    }

    final existing = await MediaThumbCache.getIfExists(widget.file);
    if (existing != null) {
      if (mounted) {
        setState(() {
          _cachedFile = existing;
          _loading = false;
        });
      }
      return;
    }

    if (mounted && !_loading) setState(() => _loading = true);
    try {
      final file = await MediaThumbCache.ensureThumbnail(widget.file);
      if (mounted) {
        setState(() {
          _cachedFile = file;
          _loading = false;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _load() async {
    if (_isVideo) {
      await _loadVideoThumb();
      return;
    }

    // Локальный файл / маленькие bytes — рисуем сразу в build(), кэш не нужен.
    final localPath = widget.file.URL?.trim() ?? '';
    final hasLocal = localPath.isNotEmpty &&
        !localPath.startsWith('http') &&
        File(localPath).existsSync();
    final smallBytes = widget.file.bytes != null &&
        widget.file.bytes!.isNotEmpty &&
        widget.file.bytes!.length < 2 * 1024 * 1024;
    if (hasLocal || smallBytes) return;

    if (!MediaThumbCache.needsRemoteThumbnail(widget.file)) {
      return;
    }

    if (_cachedFile != null) {
      try {
        final file = await MediaThumbCache.ensureThumbnail(widget.file);
        if (mounted && _cachedFile?.path != file.path) {
          setState(() => _cachedFile = file);
        }
      } catch (_) {}
      return;
    }

    final existing = await MediaThumbCache.getIfExists(widget.file);
    if (existing != null) {
      if (mounted) {
        setState(() {
          _cachedFile = existing;
          _loading = false;
        });
      }
      return;
    }

    if (mounted && !_loading) setState(() => _loading = true);

    try {
      final file = await MediaThumbCache.ensureThumbnail(widget.file);
      if (mounted) {
        setState(() {
          _cachedFile = file;
          _loading = false;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final w = widget.width;
    final h = widget.height;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Ограничиваем декод нативным движком — не больше ~512 логических px.
    final cw = (w * dpr).round().clamp(1, 1024);
    final ch = (h * dpr).round().clamp(1, 1024);

    // Видео: JPEG-кадр (macOS) или живой VideoPlayer (Windows / fallback).
    if (_isVideo) {
      if (_cachedFile != null) {
        return Image.file(
          _cachedFile!,
          key: ValueKey('vthumb_${_stableKey(file)}'),
          width: w,
          height: h,
          fit: widget.fit,
          gaplessPlayback: true,
          cacheWidth: cw,
          cacheHeight: ch,
          filterQuality: FilterQuality.low,
          frameBuilder: _frameBuilder,
          errorBuilder: (_, __, ___) => InlineVideoPreview(
            file: file,
            width: w,
            height: h,
            fit: widget.fit,
          ),
        );
      }
      // Windows: native extract нет — сразу кадр через video_player.
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || _error)) {
        return InlineVideoPreview(
          key: ValueKey('vplay_${_stableKey(file)}'),
          file: file,
          width: w,
          height: h,
          fit: widget.fit,
        );
      }
      if (_error) return _blank(w, h);
      return _blank(w, h);
    }

    // Локальный путь важнее bytes: один Image.file от drop до эха сервера,
    // без мигания при появлении сжатого JPEG в памяти.
    final localPath = file.URL?.trim() ?? '';
    if (localPath.isNotEmpty && !localPath.startsWith('http')) {
      final local = File(localPath);
      if (local.existsSync()) {
        return Image.file(
          local,
          key: ValueKey('local_$localPath'),
          width: w,
          height: h,
          fit: widget.fit,
          gaplessPlayback: true,
          cacheWidth: cw,
          cacheHeight: ch,
          filterQuality: FilterQuality.low,
          frameBuilder: _frameBuilder,
          errorBuilder: (_, __, ___) => _blank(w, h),
        );
      }
    }

    // Сжатый JPEG после prepare / upload (если локального пути нет).
    if (file.bytes != null &&
        file.bytes!.isNotEmpty &&
        file.bytes!.length < 2 * 1024 * 1024) {
      return Image.memory(
        file.bytes!,
        key: ValueKey('bytes_${_stableKey(file)}_${file.bytes!.length}'),
        width: w,
        height: h,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: cw,
        cacheHeight: ch,
        filterQuality: FilterQuality.low,
        frameBuilder: _frameBuilder,
        errorBuilder: (_, __, ___) => _blank(w, h),
      );
    }

    if (_cachedFile != null) {
      return Image.file(
        _cachedFile!,
        key: ValueKey('file_${_stableKey(file)}'),
        width: w,
        height: h,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: cw,
        cacheHeight: ch,
        filterQuality: FilterQuality.low,
        frameBuilder: _frameBuilder,
        errorBuilder: (_, __, ___) => _blank(w, h),
      );
    }

    // Загрузка / ошибка — нейтральный фон, без градиента и иконок.
    return _blank(w, h);
  }

  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    // Не подменять кадр blank — иначе мигание при смене Image/декоде.
    return child;
  }

  Widget _blank(double w, double h) {
    return SizedBox(
      width: w,
      height: h,
      child: const ColoredBox(color: Color(0x22000000)),
    );
  }

  static String _stableKey(MediaFile file) {
    final local = file.URL?.trim() ?? '';
    if (local.isNotEmpty && !local.startsWith('http')) return 'p_$local';
    if (file.fname.isNotEmpty) {
      return 'f_${file.fdir}_${file.fname}_${file.size}';
    }
    if (file.hash.isNotEmpty) return 'h_${file.hash}';
    if (file.url.isNotEmpty) return 'u_${file.url}';
    return 'k_${file.kind}_${file.size}';
  }
}
