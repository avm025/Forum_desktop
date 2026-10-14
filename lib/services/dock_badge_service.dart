import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Счётчик на иконке в Dock (macOS), как Telegram Desktop.
class DockBadgeService {
  DockBadgeService._();

  static final DockBadgeService instance = DockBadgeService._();

  static const _channel = MethodChannel('forum.me/badge');

  int _last = -1;

  Future<void> setCount(int count) async {
    if (kIsWeb || !Platform.isMacOS) return;
    final n = count < 0 ? 0 : count;
    if (n == _last) return;
    _last = n;
    try {
      await _channel.invokeMethod<void>('setBadge', n);
    } catch (_) {}
  }

  Future<void> clear() => setCount(0);
}
