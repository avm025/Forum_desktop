import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PDF через нативный PDFKit (macOS), без pdfx.
class NativePdfView extends StatelessWidget {
  final String path;

  const NativePdfView({super.key, required this.path});

  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) {
      return const Center(child: Text('PDF доступен только на macOS'));
    }

    return AppKitView(
      viewType: 'forum/pdf-view',
      layoutDirection: TextDirection.ltr,
      creationParams: {'path': path},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
