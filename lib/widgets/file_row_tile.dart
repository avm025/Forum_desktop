import 'package:flutter/material.dart';

import '../models/media_file.dart';
import '../theme/app_theme.dart';

/// Одна строка файла в сообщении (порт FileRowView из FileMessageCell.swift).
class FileRowTile extends StatelessWidget {
  final MediaFile file;
  final bool onAccent;
  final double? maxWidth;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;

  const FileRowTile({
    super.key,
    required this.file,
    required this.onAccent,
    this.maxWidth,
    this.onTap,
    this.onDownload,
  });

  static const _iconSize = 44.0;
  static const _gapBeforeText = 10.0;
  static const _gapBeforeAction = 8.0;
  static const _actionIconSize = 20.0;

  String get _title {
    if (file.title.isNotEmpty) return file.title;
    if (file.fname.isNotEmpty) return file.fname;
    return 'Документ';
  }

  String get _meta {
    final ext = file.kind.isNotEmpty
        ? file.kind.toUpperCase()
        : file.formatLabel;
    final size = file.humanSize;
    if (size.isEmpty && ext.isEmpty) return '';
    if (size.isEmpty) return ext;
    if (ext.isEmpty) return size;
    return '$size · $ext';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final iconBg = onAccent
        ? Colors.white.withValues(alpha: 0.22)
        : p.purple.withValues(alpha: 0.15);
    final titleColor = onAccent ? Colors.white : p.text1;
    final metaColor = onAccent ? Colors.white70 : p.text2;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: maxWidth != null
            ? BoxConstraints(maxWidth: maxWidth!)
            : const BoxConstraints(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _iconSize,
                        height: _iconSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            Icons.insert_drive_file_outlined,
                            color: onAccent ? Colors.white : p.purple,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: _gapBeforeText),
                      Expanded(
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
                            if (_meta.isNotEmpty)
                              Text(
                                _meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(color: metaColor, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: _gapBeforeAction),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onDownload,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.file_download_outlined,
                      color: metaColor,
                      size: _actionIconSize,
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
