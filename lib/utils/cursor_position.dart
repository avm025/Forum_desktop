import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/api_logger.dart';

/// Снимок курсора: позиция + состояние ЛКМ.
class CursorSnapshot {
  final Offset position;
  final bool primaryDown;

  const CursorSnapshot({
    required this.position,
    required this.primaryDown,
  });
}

/// Картинка из буфера, уже сжатая нативно (JPEG ≤1280).
class ClipboardImageFile {
  final String path;
  final String fileName;
  final String width;
  final String height;
  final int size;

  const ClipboardImageFile({
    required this.path,
    required this.fileName,
    required this.width,
    required this.height,
    required this.size,
  });

  static ClipboardImageFile? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final path = raw['path']?.toString();
    if (path == null || path.isEmpty) return null;
    return ClipboardImageFile(
      path: path,
      fileName: raw['fileName']?.toString() ?? 'screenshot.jpg',
      width: raw['width']?.toString() ?? '',
      height: raw['height']?.toString() ?? '',
      size: (raw['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Позиция курсора + clipboard image (macOS).
class CursorPosition {
  CursorPosition._();

  static const _channel = MethodChannel('forum_app/cursor');

  static void Function(ClipboardImageFile file)? onClipboardImage;

  static bool _handlerInstalled = false;

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  static void _ensureHandler() {
    if (_handlerInstalled || !isSupported) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onClipboardImage') {
        final file = ClipboardImageFile.fromMap(call.arguments);
        ApiLogger.instance.logEvent(
          'PASTE',
          file == null
              ? 'native onClipboardImage=null'
              : 'native onClipboardImage ${file.fileName} '
                  '${file.width}x${file.height} ${file.size}b',
        );
        if (file != null) {
          onClipboardImage?.call(file);
        }
      }
    });
  }

  /// Включить перехват Cmd+V на уровне NSEvent (пока фокус в композере).
  static Future<void> setImagePasteIntercept(bool enabled) async {
    if (!isSupported) return;
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('setImagePasteIntercept', enabled);
      ApiLogger.instance.logEvent(
        'PASTE',
        'intercept=${enabled ? 'on' : 'off'}',
      );
    } catch (e) {
      ApiLogger.instance.logEvent('PASTE', 'intercept error: $e');
    }
  }

  static Future<Offset?> get() async {
    final snap = await getSnapshot();
    return snap?.position;
  }

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

  static Future<bool> hasClipboardImage() async {
    if (!isSupported) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>('hasClipboardImage');
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  static Future<ClipboardImageFile?> saveClipboardImage() async {
    if (!isSupported) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>('saveClipboardImage');
      return ClipboardImageFile.fromMap(raw);
    } catch (_) {
      return null;
    }
  }
}
