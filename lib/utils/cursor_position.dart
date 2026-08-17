import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Снимок курсора: позиция + состояние ЛКМ.
class CursorSnapshot {
  final Offset position;
  final bool primaryDown;

  const CursorSnapshot({
    required this.position,
    required this.primaryDown,
  });
}

/// Позиция курсора в логических координатах окна (Flutter, top-left).
class CursorPosition {
  CursorPosition._();

  static const _channel = MethodChannel('forum_app/cursor');

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  static Future<Offset?> get() async {
    final snap = await getSnapshot();
    return snap?.position;
  }

  /// Позиция + [primaryDown] (левая кнопка). Нужно для мгновенного
  /// старта return-анимации: native DnD отдаёт `dragging=false` с задержкой.
  static Future<CursorSnapshot?> getSnapshot() async {
    if (!isSupported) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getPosition');
      if (raw is! Map) return null;
      final x = (raw['x'] as num?)?.toDouble();
      final y = (raw['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      final primaryDown = raw['primaryDown'] == true;
      return CursorSnapshot(
        position: Offset(x, y),
        primaryDown: primaryDown,
      );
    } catch (_) {
      return null;
    }
  }
}
