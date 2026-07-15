import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Лог запросов/ответов к серверу в файл + память для UI.
/// Запись асинхронная и не блокирует сетевые запросы.
class ApiLogger extends ChangeNotifier {
  ApiLogger._();
  static final ApiLogger instance = ApiLogger._();

  static const _fileName = 'forum_api.log';
  static const _maxPayloadChars = 4096;

  final _buffer = StringBuffer();
  File? _logFile;
  bool _ready = false;
  Timer? _flushTimer;
  Timer? _notifyTimer;
  bool _flushInProgress = false;
  bool _flushScheduled = false;

  String get content => _buffer.toString();

  Future<void> init() async {
    if (_ready) return;
    try {
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        _logFile = File('${dir.path}/$_fileName');
        if (await _logFile!.exists()) {
          final existing = await _logFile!.readAsString();
          if (existing.length > 256 * 1024) {
            _buffer.write(existing.substring(existing.length - 256 * 1024));
          } else {
            _buffer.write(existing);
          }
        }
      }
      _ready = true;
    } catch (_) {
      _ready = true;
    }
  }

  void logWsSend(String type, Object? payload) {
    _appendBlock('''
========== ${_ts()} ==========
[WS →] $type
${formatPayload(payload)}
''');
  }

  void logWsReceive(
    String type,
    Object? payload, {
    Duration? duration,
  }) {
    final ms = duration != null ? ' (${duration.inMilliseconds} ms)' : '';
    _appendBlock('''
[WS ←] $type$ms
${formatPayload(payload)}
''');
  }

  void logHttpSend(String method, String url, Object? payload) {
    _appendBlock('''
========== ${_ts()} ==========
[HTTP →] $method $url
${formatPayload(payload)}
''');
  }

  void logHttpReceive(
    int statusCode,
    Object? payload, {
    Duration? duration,
  }) {
    final ms = duration != null ? ' (${duration.inMilliseconds} ms)' : '';
    _appendBlock('''
[HTTP ←] $statusCode$ms
${formatPayload(payload)}
''');
  }

  void logEvent(String title, String body) {
    _appendBlock('''
========== ${_ts()} ==========
[$title]
$body
''');
  }

  Future<void> clear() async {
    _buffer.clear();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
    notifyListeners();
  }

  void _appendBlock(String text) {
    if (!_ready) {
      unawaited(init().then((_) => _appendBlock(text)));
      return;
    }
    _buffer.writeln(text);
    _scheduleFlush();
    _scheduleNotify();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      _flushScheduled = false;
      unawaited(_flushToDisk());
    });
  }

  void _scheduleNotify() {
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(milliseconds: 400), () {
      notifyListeners();
    });
  }

  Future<void> _flushToDisk() async {
    if (_logFile == null || _flushInProgress) return;
    _flushInProgress = true;
    try {
      final snapshot = _buffer.toString();
      await _logFile!.writeAsString(snapshot, flush: true);
    } catch (_) {
    } finally {
      _flushInProgress = false;
    }
  }

  String _ts() => DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());

  /// Компактный JSON для лога с обрезкой больших тел.
  static String formatPayload(Object? data) {
    if (data == null) return '';
    try {
      String raw;
      if (data is String) {
        raw = data;
      } else {
        raw = jsonEncode(data);
      }
      return _truncate(raw);
    } catch (_) {
      return _truncate(data.toString());
    }
  }

  static String _truncate(String s) {
    if (s.length <= _maxPayloadChars) return s;
    return '${s.substring(0, _maxPayloadChars)}\n'
        '... [обрезано, всего ${s.length} символов]';
  }

  /// Красивый JSON (только для небольших объектов в UI).
  static String prettyJson(Object? data) => formatPayload(data);
}
