import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Системный fullscreen окна приложения (весь монитор).
class WindowFullscreen {
  WindowFullscreen._();

  static const _channel = MethodChannel('forum_app/window');

  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  static Future<bool> isFullscreen() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isFullscreen');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Входит в системный fullscreen и ждёт завершения анимации.
  static Future<bool> enter() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('enterFullscreen');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Выходит из fullscreen и ждёт завершения анимации.
  static Future<bool> exit() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('exitFullscreen');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
