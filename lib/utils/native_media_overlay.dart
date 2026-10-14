import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_config.dart';
import '../models/media_file.dart';
import 'attachment_kind.dart';
import 'media_file_loader.dart';
import 'media_file_url.dart';
import 'media_viewer_context.dart';

typedef MediaOverlayActionHandler = Future<void> Function(String action);

/// Нативный оверлей на весь монитор (blur). Окно приложения не трогает.
class NativeMediaOverlay {
  NativeMediaOverlay._();

  static const _channel = MethodChannel('forum_app/media_overlay');

  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  static MediaOverlayActionHandler? _actionHandler;
  static VoidCallback? _dismissAppUi;
  static bool _forwardBusy = false;

  /// Готовит файл и показывает оверлей. `false` — нужен Flutter-fallback.
  static Future<bool> showFile(
    MediaFile file, {
    MediaViewerContext? context,
    MediaOverlayActionHandler? onAction,
  }) async {
    if (!isSupported) return false;
    final kind = AttachmentKind.of(file);
    _actionHandler = onAction;
    _forwardBusy = false;
    _channel.setMethodCallHandler(_onMethodCall);
    try {
      switch (kind) {
        case AttachmentViewKind.image:
          return await _showImage(file, context);
        case AttachmentViewKind.video:
          return await _showVideo(file, context);
        case AttachmentViewKind.pdf:
          return await _showPdf(file, context);
        case AttachmentViewKind.text:
          return await _showText(file, context);
        case AttachmentViewKind.other:
          return false;
      }
    } finally {
      _channel.setMethodCallHandler(null);
      _actionHandler = null;
      _dismissAppUi = null;
      _forwardBusy = false;
      try {
        await _channel.invokeMethod<void>('restoreOverlay');
      } catch (_) {}
    }
  }

  static Future<void> prepareForAppUi() async {
    try {
      await _channel.invokeMethod<void>('prepareForAppUi');
    } catch (_) {}
  }

  static Future<void> revealAppUi() async {
    try {
      await _channel.invokeMethod<void>('revealAppUi');
    } catch (_) {}
  }

  static Future<void> restoreOverlay() async {
    try {
      await _channel.invokeMethod<void>('restoreOverlay');
    } catch (_) {}
  }

  /// Регистрирует закрытие окна пересылки (клик снаружи / назад).
  static void setDismissAppUiHandler(VoidCallback? handler) {
    _dismissAppUi = handler;
  }

  static bool get isForwardBusy => _forwardBusy;

  static void setForwardBusy(bool value) {
    _forwardBusy = value;
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'dismissAppUi') {
      debugPrint('[NativeMediaOverlay] dismissAppUi');
      _dismissAppUi?.call();
      return null;
    }

    if (call.method != 'action') return null;
    final args = call.arguments;
    final action = args is Map ? args['action']?.toString() : null;
    if (action == null || action.isEmpty) return null;

    // forward — сразу отпускаем channel, иначе повторный вызов ломается.
    if (action == 'forward') {
      debugPrint('[NativeMediaOverlay] action=forward busy=$_forwardBusy');
      final handler = _actionHandler;
      if (handler != null) {
        // Не через microtask-цепочку, которая может схлопнуться с dismiss.
        Future<void>.delayed(Duration.zero, () => handler(action));
      }
      return null;
    }

    return null;
  }

  static Future<bool> _showImage(
    MediaFile file,
    MediaViewerContext? ctx,
  ) async {
    final downloadUrl =
        ApiConfig.rewriteLegacyHost(MediaFileUrl.resolve(file));

    try {
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        final path = await MediaFileLoader.ensureCached(file);
        return _invoke(kind: 'image', path: path, context: ctx);
      }

      final cached = await MediaFileLoader.cachedPathIfExists(
        file,
        downloadUrl: downloadUrl,
      );
      if (cached != null) {
        return _invoke(kind: 'image', path: cached, context: ctx);
      }

      final local = file.URL?.trim() ?? '';
      if (local.isNotEmpty &&
          !local.startsWith('http') &&
          File(local).existsSync()) {
        return _invoke(kind: 'image', path: local, context: ctx);
      }

      if (downloadUrl.startsWith('http')) {
        final ok = await _invoke(
          kind: 'image',
          url: downloadUrl,
          headers: ApiConfig.fileHeaders,
          context: ctx,
        );
        if (ok) return true;
        final path = await MediaFileLoader.ensureCached(
          file,
          downloadUrl: downloadUrl,
        );
        return _invoke(kind: 'image', path: path, context: ctx);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<bool> _showVideo(
    MediaFile file,
    MediaViewerContext? ctx,
  ) async {
    final downloadUrl =
        ApiConfig.rewriteLegacyHost(MediaFileUrl.resolve(file));

    try {
      final cached = await MediaFileLoader.cachedPathIfExists(
        file,
        downloadUrl: downloadUrl,
      );
      if (cached != null) {
        return _invoke(kind: 'video', path: cached, context: ctx);
      }

      final local = file.URL?.trim() ?? '';
      if (local.isNotEmpty &&
          !local.startsWith('http') &&
          File(local).existsSync()) {
        return _invoke(kind: 'video', path: local, context: ctx);
      }

      if (downloadUrl.startsWith('http')) {
        final streamed = await _invoke(
          kind: 'video',
          url: downloadUrl,
          headers: ApiConfig.fileHeaders,
          context: ctx,
        );
        if (streamed) return true;
        final path = await MediaFileLoader.ensureCached(
          file,
          downloadUrl: downloadUrl,
        );
        return _invoke(kind: 'video', path: path, context: ctx);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<bool> _showPdf(
    MediaFile file,
    MediaViewerContext? ctx,
  ) async {
    try {
      final path = await MediaFileLoader.ensureCached(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
      return _invoke(kind: 'pdf', path: path, context: ctx);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _showText(
    MediaFile file,
    MediaViewerContext? ctx,
  ) async {
    try {
      final path = await MediaFileLoader.ensureCached(
        file,
        downloadUrl: MediaFileUrl.resolve(file),
      );
      return _invoke(kind: 'text', path: path, context: ctx);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _invoke({
    required String kind,
    String? path,
    String? url,
    Map<String, String>? headers,
    String? text,
    MediaViewerContext? context,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'kind': kind,
        if (path != null && path.isNotEmpty) 'path': path,
        if (url != null && url.isNotEmpty) 'url': url,
        if (headers != null && headers.isNotEmpty) 'headers': headers,
        if (text != null) 'text': text,
        if (context != null) ...{
          if (context.chatTitle.isNotEmpty) 'chatTitle': context.chatTitle,
          if (context.dateLabel.isNotEmpty) 'dateLabel': context.dateLabel,
        },
      });
      return true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
