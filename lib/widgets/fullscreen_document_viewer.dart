import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_file.dart';
import '../utils/attachment_kind.dart';
import '../utils/file_opener.dart';
import '../utils/media_display_name.dart';
import '../utils/media_file_loader.dart';
import 'native_pdf_view.dart';

/// Просмотр PDF и текстовых файлов в чате.
class FullscreenDocumentViewer extends StatefulWidget {
  final MediaFile file;

  const FullscreenDocumentViewer({super.key, required this.file});

  static Future<void> show(BuildContext context, MediaFile file) {
    return showDialog<void>(
      context: context,
      builder: (_) => FullscreenDocumentViewer(file: file),
    );
  }

  @override
  State<FullscreenDocumentViewer> createState() =>
      _FullscreenDocumentViewerState();
}

class _FullscreenDocumentViewerState extends State<FullscreenDocumentViewer> {
  String? _pdfPath;
  String? _textContent;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final source = await MediaFileLoader.resolve(widget.file);
      final kind = AttachmentKind.of(widget.file);

      if (kind == AttachmentViewKind.pdf) {
        final path = await _pdfLocalPath(source);
        if (!mounted) return;
        setState(() {
          _pdfPath = path;
          _loading = false;
        });
        return;
      }

      if (kind == AttachmentViewKind.text) {
        String text;
        if (source.hasBytes) {
          text = utf8.decode(source.bytes!, allowMalformed: true);
        } else if (source.hasLocalPath) {
          text = await File(source.localPath!).readAsString();
        } else {
          throw StateError('Нет данных файла');
        }
        if (!mounted) return;
        setState(() {
          _textContent = text;
          _loading = false;
        });
        return;
      }

      throw StateError('Неподдерживаемый тип');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<String> _pdfLocalPath(MediaFileSource source) async {
    if (source.hasLocalPath) return source.localPath!;
    if (source.hasBytes) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/forum_pdf_${widget.file.hash}.pdf');
      await file.writeAsBytes(source.bytes!, flush: true);
      return file.path;
    }
    throw StateError('Нет данных PDF');
  }

  @override
  Widget build(BuildContext context) {
    final title = MediaDisplayName.forFile(widget.file);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 32,
          maxHeight: MediaQuery.sizeOf(context).height - 80,
        ),
        child: Column(
          children: [
            _header(context, title),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось открыть документ'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await FileOpener.open(widget.file);
                  if (ok && context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Открыть в системе'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pdfPath != null) {
      if (NativePdfView.isSupported) {
        return NativePdfView(path: _pdfPath!);
      }
      return Center(
        child: FilledButton.icon(
          onPressed: () async {
            final ok = await FileOpener.open(widget.file);
            if (ok && context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('Открыть PDF'),
        ),
      );
    }
    if (_textContent != null) {
      return Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _textContent!,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
