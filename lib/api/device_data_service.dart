import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Формирование payload для WS `device` (см. WS_DEVICE.md).
class DeviceDataService {
  DeviceDataService._();

  static const _throttleKey = 'forum_last_send_device';
  static const _throttleSeconds = 5;
  static const _appVersion = '1.0.0';

  /// Не чаще одного раза в 5 секунд (как `mustExecFromLastTime` в iOS).
  static Future<bool> shouldSend() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_throttleKey);
    if (lastMs == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    return elapsed >= _throttleSeconds * 1000;
  }

  static Future<void> markSent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_throttleKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// `uid` — тот же UUID, что в `log_in`.
  static Future<Map<String, dynamic>> buildPayload(
    String uid, {
    String fcmToken = '',
  }) async {
    if (kIsWeb) {
      return {
        'os': 'web',
        'model': 'browser',
        'app': _appVersion,
        'os_ver': '',
        'hardware': _emptyHardware(),
        'uid': uid,
        'token': fcmToken,
      };
    }

    final hardware = await _hardwareInfo();
    if (Platform.isMacOS) {
      return {
        'os': 'macOS',
        'model': await _macModel(),
        'app': _appVersion,
        'os_ver': _osVer(),
        'hardware': hardware,
        'uid': uid,
        'token': fcmToken,
      };
    }

    if (Platform.isIOS) {
      return {
        'os': 'iOS',
        'model': Platform.localHostname,
        'app': _appVersion,
        'os_ver': _osVer(),
        'hardware': hardware,
        'uid': uid,
        'token': fcmToken,
      };
    }

    return {
      'os': Platform.operatingSystem,
      'model': Platform.localHostname,
      'app': _appVersion,
      'os_ver': _osVer(),
      'hardware': hardware,
      'uid': uid,
      'token': fcmToken,
    };
  }

  /// macOS/iOS: `Version 15.3.1 (Build 24D70)` → `15.3.1 (24D70)` (лимит БД 20 символов).
  static String _osVer() {
    return Platform.operatingSystemVersion
        .replaceAll('Version ', '')
        .replaceAll('Build ', '');
  }

  static Map<String, dynamic> _emptyHardware() => {
        'cores': 1,
        'RAM': '0 GB',
        'HDD': '0 GB',
        'HDD_free': '0 GB',
      };

  static Future<Map<String, dynamic>> _hardwareInfo() async {
    final cores = Platform.numberOfProcessors;
    final ram = await _ramGb();
    final storage = await _storageGb();
    return {
      'cores': cores,
      'RAM': ram,
      'HDD': storage.$1,
      'HDD_free': storage.$2,
    };
  }

  static Future<String> _ramGb() async {
    if (Platform.isMacOS || Platform.isIOS) {
      final bytes = await _sysctlInt('hw.memsize');
      if (bytes != null && bytes > 0) {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      }
    }
    return '0 GB';
  }

  static Future<(String, String)> _storageGb() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return ('0 GB', '0 GB');
    }
    try {
      final result = await Process.run('df', ['-k', '/']);
      if (result.exitCode != 0) return ('0 GB', '0 GB');
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return ('0 GB', '0 GB');
      final parts = lines[1].split(RegExp(r'\s+'));
      if (parts.length < 4) return ('0 GB', '0 GB');
      final totalKb = int.tryParse(parts[1]) ?? 0;
      final availKb = int.tryParse(parts[3]) ?? 0;
      final totalGb = (totalKb / (1024 * 1024)).round();
      final freeGb = (availKb / (1024 * 1024)).round();
      return ('$totalGb GB', '$freeGb GB');
    } catch (_) {
      return ('0 GB', '0 GB');
    }
  }

  static Future<String> _macModel() async {
    final model = await _sysctlString('hw.model');
    if (model != null && model.isNotEmpty) return model;
    return Platform.localHostname;
  }

  static Future<int?> _sysctlInt(String name) async {
    final raw = await _sysctlString(name);
    return raw != null ? int.tryParse(raw) : null;
  }

  static Future<String?> _sysctlString(String name) async {
    if (!Platform.isMacOS && !Platform.isIOS) return null;
    try {
      final result = await Process.run('sysctl', ['-n', name]);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }
}
