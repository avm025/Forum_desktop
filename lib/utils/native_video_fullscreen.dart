import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Нативный fullscreen только для видео (отдельное окно, не всё приложение).
class NativeVideoFullscreen {
  NativeVideoFullscreen._();

  static const _channel = MethodChannel('forum_app/video_player');

  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  /// Открывает видео на весь экран. Completer завершается при закрытии плеера.
  /// Возвращает `false`, если нативный плеер недоступен / ошибка старта.
  static Future<bool> play({
    String? path,
    String? url,
    Map<String, String>? headers,
  }) async {
    if (!isSupported) return false;
    final p = path?.trim() ?? '';
    final u = url?.trim() ?? '';
    if (p.isEmpty && u.isEmpty) return false;
    try {
      await _channel.invokeMethod<void>('playFullscreen', {
        if (p.isNotEmpty) 'path': p,
        if (u.isNotEmpty) 'url': u,
        if (headers != null && headers.isNotEmpty) 'headers': headers,
      });
      return true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
