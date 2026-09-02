import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import '../services/media_thumb_cache.dart';
import '../theme/app_theme.dart';
import '../utils/file_kind.dart';
import '../utils/file_opener.dart';
import '../utils/media_display_name.dart';
import '../utils/media_file_loader.dart';
import '../utils/media_file_url.dart';

/// Одна строка файла в сообщении.
///
/// Превью показывается сразу (если есть). Не загружен: стрелка как в Telegram.
/// Загружен: превью / тип файла + «Показать в папке».
class FileRowTile extends StatefulWidget {
  final MediaFile file;
  final bool onAccent;
  final bool selected;
  final double? maxWidth;
  final VoidCallback? onTap;

  const FileRowTile({
    super.key,
    required this.file,
    required this.onAccent,
    this.selected = false,
    this.maxWidth,
    this.onTap,
  });

  /// Было 44; +30% ≈ 57.
  static const _iconSize = 57.0;
  static const _iconRadius = 12.0;
  static const _gapBeforeText = 10.0;

  @override
  State<FileRowTile> createState() => _FileRowTileState();
}

class _FileRowTileState extends State<FileRowTile> {
  String? _localPath;
  bool _checking = true;
  bool _busy = false;
  ImageProvider? _preview;

  MediaFile get file => widget.file;
  bool get _downloaded =>
      _localPath != null ||
      (file.bytes != null && file.bytes!.isNotEmpty);

  String get _title => MediaDisplayName.forFile(file);

  String get _sizeLabel => file.humanSize;

  String get _extLabel {
    final ext = file.kind.isNotEmpty
        ? file.kind.toUpperCase()
        : file.formatLabel;
    return ext;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant FileRowTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.hash != widget.file.hash ||
        oldWidget.file.url != widget.file.url ||
        oldWidget.file.URL != widget.file.URL ||
        oldWidget.file.preview != widget.file.preview) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _checking = true;
      _preview = null;
      _localPath = null;
    });

    // Превью грузим сразу, не дожидаясь скачивания файла.
    final previewFuture = _loadPreview();

    if (file.bytes != null && file.bytes!.isNotEmpty) {
      if (_looksLikeImage && _preview == null) {
        _preview = MemoryImage(file.bytes!);
      }
      if (mounted) {
        setState(() {
          _checking = false;
          _localPath = file.URL;
        });
      }
      await previewFuture;
      return;
    }

    final url = MediaFileUrl.resolve(file);
    final cached = await MediaFileLoader.cachedPathIfExists(
      file,
      downloadUrl: url,
    );
    if (!mounted) return;

    if (cached != null) {
      file.URL = cached;
      setState(() {
        _localPath = cached;
        _checking = false;
      });
    } else if (mounted) {
      setState(() => _checking = false);
    }

    await previewFuture;
  }

  bool get _looksLikeImage {
    final kind = file.kind.toLowerCase();
    final ext = FileKind.extensionFromName(
      file.fname.isNotEmpty ? file.fname : file.title,
    );
    const images = {
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
    };
    return images.contains(kind) || images.contains(ext);
  }

  Future<void> _loadPreview() async {
    final previewUrl = file.preview.trim();
    if (previewUrl.startsWith('http://') || previewUrl.startsWith('https://')) {
      if (mounted) {
        setState(
          () => _preview = CachedNetworkImageProvider(
            previewUrl,
            headers: ApiConfig.fileHeaders,
          ),
        );
      }
      return;
    }

    if (previewUrl.isNotEmpty && !previewUrl.startsWith('http')) {
      final local = File(
        previewUrl.startsWith('file://')
            ? Uri.parse(previewUrl).toFilePath()
            : previewUrl,
      );
      if (await local.exists()) {
        if (mounted) setState(() => _preview = FileImage(local));
        return;
      }
    }

    if (_looksLikeImage || file.isVideo) {
      try {
        final thumb = await MediaThumbCache.ensureThumbnail(file);
        if (mounted) setState(() => _preview = FileImage(thumb));
        return;
      } catch (_) {}
    }

    final path = _localPath ?? file.URL;
    if (path != null && path.isNotEmpty && _looksLikeImage) {
      final local = File(path);
      if (await local.exists()) {
        if (mounted) setState(() => _preview = FileImage(local));
      }
    }
  }

  Future<void> _download() async {
    if (_busy || _downloaded) return;
    setState(() => _busy = true);
    try {
      final path = await MediaFileLoader.ensureCached(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
      file.URL = path;
      if (!mounted) return;
      setState(() {
        _localPath = path;
        _busy = false;
      });
      if (_preview == null) await _loadPreview();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить файл')),
      );
    }
  }

  Future<void> _reveal() async {
    var local = _localPath ?? file.URL;
    if ((local == null || local.isEmpty) &&
        file.bytes != null &&
        file.bytes!.isNotEmpty) {
      try {
        local = await MediaFileLoader.ensureCached(
          file,
          downloadUrl: MediaFileUrl.resolve(file),
        );
        file.URL = local;
        if (mounted) setState(() => _localPath = local);
      } catch (_) {
        local = null;
      }
    }
    if (local == null || local.isEmpty) return;
    final ok = await FileOpener.revealInFolder(local);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть папку')),
      );
    }
  }

  void _onLeadingTap() {
    if (_busy || _checking) return;
    // «Показать в папке» — только по текстовой кнопке; превью только загружает.
    if (!_downloaded) {
      _download();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onAccent = widget.onAccent;
    final iconBg = onAccent
        ? Colors.white.withValues(alpha: 0.22)
        : p.purple.withValues(alpha: 0.15);
    final titleColor = onAccent ? Colors.white : p.text1;
    final metaColor = onAccent ? Colors.white70 : p.text2;
    final actionColor = onAccent ? p.lime : p.purple;

    final textMaxWidth = widget.maxWidth != null
        ? (widget.maxWidth! -
            FileRowTile._iconSize -
            FileRowTile._gapBeforeText -
            8)
        : 260.0;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: widget.maxWidth != null
            ? BoxConstraints(maxWidth: widget.maxWidth!)
            : const BoxConstraints(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: widget.selected
                ? (onAccent
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0x1A2E7CF6))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _onLeadingTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _LeadingIcon(
                        size: FileRowTile._iconSize,
                        radius: FileRowTile._iconRadius,
                        background: iconBg,
                        onAccent: onAccent,
                        purple: p.purple,
                        checking: _checking,
                        busy: _busy,
                        downloaded: _downloaded,
                        preview: _preview,
                        ext: _extLabel,
                      ),
                      if (widget.selected)
                        const Positioned(
                          top: -2,
                          right: -2,
                          child: _TelegramCheckBadge(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: FileRowTile._gapBeforeText),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_sizeLabel.isNotEmpty || _extLabel.isNotEmpty)
                            Flexible(
                              child: Text(
                                [
                                  if (_sizeLabel.isNotEmpty) _sizeLabel,
                                  if (_extLabel.isNotEmpty) _extLabel,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(
                                  color: metaColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (_sizeLabel.isNotEmpty || _extLabel.isNotEmpty)
                            const SizedBox(width: 8),
                          _ActionTextButton(
                            label: _downloaded
                                ? 'Показать в папке'
                                : 'Загрузить',
                            color: actionColor,
                            enabled: !_checking && !_busy,
                            onTap: _downloaded ? _reveal : _download,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTextButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTextButton({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: enabled ? color : color.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  final double size;
  final double radius;
  final Color background;
  final bool onAccent;
  final Color purple;
  final bool checking;
  final bool busy;
  final bool downloaded;
  final ImageProvider? preview;
  final String ext;

  const _LeadingIcon({
    required this.size,
    required this.radius,
    required this.background,
    required this.onAccent,
    required this.purple,
    required this.checking,
    required this.busy,
    required this.downloaded,
    required this.preview,
    required this.ext,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onAccent ? Colors.white : purple;
    final showProgress = checking || busy;
    final showDownload = !downloaded && !showProgress;

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                Image(
                  image: preview!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _ExtPreview(ext: ext, color: fg),
                )
              else
                _ExtPreview(ext: ext, color: fg),
              if (showDownload)
                ColoredBox(
                  color: Colors.black.withValues(alpha: preview != null ? 0.28 : 0),
                  child: Center(
                    child: _TelegramDownloadBadge(
                      color: purple,
                      onAccent: onAccent,
                      hasPreview: preview != null,
                    ),
                  ),
                ),
              if (showProgress)
                ColoredBox(
                  color: Colors.black.withValues(
                    alpha: preview != null ? 0.28 : 0.08,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: preview != null || onAccent
                            ? Colors.white
                            : purple,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круг со стрелкой вниз — как кнопка загрузки в Telegram Desktop.
class _TelegramDownloadBadge extends StatelessWidget {
  final Color color;
  final bool onAccent;
  final bool hasPreview;

  const _TelegramDownloadBadge({
    required this.color,
    required this.onAccent,
    required this.hasPreview,
  });

  @override
  Widget build(BuildContext context) {
    final bg = hasPreview || onAccent ? Colors.white : color;
    final arrow = hasPreview || onAccent ? color : Colors.white;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: hasPreview ? 0.95 : 1),
        shape: BoxShape.circle,
        boxShadow: hasPreview
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.arrow_downward_rounded,
        size: 18,
        color: arrow,
      ),
    );
  }
}

class _ExtPreview extends StatelessWidget {
  final String ext;
  final Color color;

  const _ExtPreview({required this.ext, required this.color});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          ext.isNotEmpty ? (ext.length > 4 ? ext.substring(0, 4) : ext) : 'FILE',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Кружок с галкой — как выделение в Telegram.
class _TelegramCheckBadge extends StatelessWidget {
  const _TelegramCheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2E7CF6),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}
