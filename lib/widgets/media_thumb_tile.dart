import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_colors.dart';

/// Превью медиа в сообщении: из дискового кэша, без повторной загрузки.
class MediaThumbTile extends StatefulWidget {
  final MediaFile file;
  final double width;
  final double height;
  final BoxFit fit;

  const MediaThumbTile({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
  });

  @override
  State<MediaThumbTile> createState() => _MediaThumbTileState();
}

class _MediaThumbTileState extends State<MediaThumbTile> {
  File? _cachedFile;
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    // Синхронный peek — без вспышки placeholder при первом кадре / ресайзе.
    _cachedFile = MediaThumbCache.peekSync(widget.file);
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sizeChanged = (oldWidget.width - widget.width).abs() > 0.5 ||
        (oldWidget.height - widget.height).abs() > 0.5;
    if (oldWidget.file.hash != widget.file.hash ||
        oldWidget.file.url != widget.file.url) {
      _cachedFile = MediaThumbCache.peekSync(widget.file);
      _error = false;
      _loading = false;
      _load();
    } else if (sizeChanged && mounted) {
      // Только перерисовать с новыми width/height — кэш не сбрасывать.
      setState(() {});
    }
  }

  Future<void> _load() async {
    if (!MediaThumbCache.needsRemoteThumbnail(widget.file)) {
      return;
    }

    if (_cachedFile != null) {
      // Уже есть из peekSync — подтянуть ensure на фоне без placeholder.
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
      if (mounted) setState(() => _cachedFile = existing);
      return;
    }

    if (mounted) setState(() => _loading = true);

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

    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return Image.memory(
        file.bytes!,
        key: ValueKey('bytes_${file.hash}'),
        width: w,
        height: h,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }

    if (_cachedFile != null) {
      return Image.file(
        _cachedFile!,
        key: ValueKey('file_${file.hash}'),
        width: w,
        height: h,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }

    if (_loading) {
      return _placeholder(w, h);
    }

    if (_error) {
      return _placeholder(w, h, error: true);
    }

    return _placeholder(w, h);
  }

  Widget _placeholder(double w, double h, {bool error = false}) {
    final media = widget.file;
    final gradient = AppColors.avatarGradientFor(
      media.hash.isNotEmpty ? media.hash : media.url,
    );
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: _loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            )
          : Icon(
              error
                  ? Icons.broken_image_outlined
                  : (media.isVideo ? Icons.videocam_outlined : Icons.image_outlined),
              color: Colors.white54,
              size: 40,
            ),
    );
  }
}
