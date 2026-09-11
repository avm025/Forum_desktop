import 'dart:math' as math;

/// Парсинг и отрисовка гистограммы голосовых (как Forum_ios `VoiceHistogram`).
///
/// В сети: hex-строка `"038CF5…"` (нибблы 0–F → 0–15) или `[Int]`.
class VoiceHistogram {
  VoiceHistogram._();

  static const maxLevel = 15;

  /// `hist` из body / `voice_histogram` с верхнего уровня msg.
  static List<int> parse(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map(_asLevel).where((v) => v >= 0).toList(growable: false);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return const [];
    if (s.startsWith('[') && s.endsWith(']')) {
      try {
        // Иногда приходит JSON-массив строкой.
        final inner = s.substring(1, s.length - 1).trim();
        if (inner.isEmpty) return const [];
        return inner
            .split(',')
            .map((e) => _asLevel(e.trim()))
            .where((v) => v >= 0)
            .toList(growable: false);
      } catch (_) {
        // fall through to hex
      }
    }
    return fromHex(s);
  }

  static List<int> fromHex(String hex) {
    final out = <int>[];
    for (final rune in hex.runes) {
      final c = String.fromCharCode(rune);
      final v = int.tryParse(c, radix: 16);
      if (v != null) out.add(v.clamp(0, maxLevel));
    }
    return out;
  }

  static String toHex(List<int> levels) {
    final buf = StringBuffer();
    for (final v in levels) {
      buf.write((v.clamp(0, maxLevel)).toRadixString(16).toUpperCase());
    }
    return buf.toString();
  }

  /// Сжимает/растягивает сэмплы под ширину волны (столбики ~2px + gap).
  static List<int> downsample(List<int> source, int barCount) {
    if (barCount <= 0) return const [];
    if (source.isEmpty) {
      return List<int>.filled(barCount, 2, growable: false);
    }
    if (source.length == barCount) return List<int>.from(source);
    if (source.length < barCount) {
      // Повтор сэмплов, чтобы заполнить ширину.
      final out = List<int>.filled(barCount, 0);
      for (var i = 0; i < barCount; i++) {
        out[i] = source[(i * source.length) ~/ barCount];
      }
      return out;
    }
    final out = List<int>.filled(barCount, 0);
    final bucket = source.length / barCount;
    for (var i = 0; i < barCount; i++) {
      final start = (i * bucket).floor();
      final end = math.min(source.length, ((i + 1) * bucket).ceil());
      var peak = 0;
      for (var j = start; j < end; j++) {
        if (source[j] > peak) peak = source[j];
      }
      out[i] = peak;
    }
    return out;
  }

  /// Заглушка, если hist нет — ровная «дыхательная» волна по длительности.
  static List<int> placeholder({required int durationSec, int bars = 48}) {
    final n = bars.clamp(24, 64);
    final out = List<int>.filled(n, 0);
    final seed = math.max(1, durationSec);
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final wave = (math.sin(t * math.pi * 4 + seed) * 0.5 + 0.5) *
          (0.35 + 0.65 * math.sin(t * math.pi));
      out[i] = (2 + wave * 10).round().clamp(1, maxLevel);
    }
    return out;
  }

  static int _asLevel(dynamic v) {
    if (v is int) return v.clamp(0, maxLevel);
    if (v is num) return v.round().clamp(0, maxLevel);
    final s = v.toString().trim();
    if (s.isEmpty) return -1;
    if (s.length == 1) {
      final hex = int.tryParse(s, radix: 16);
      if (hex != null) return hex.clamp(0, maxLevel);
    }
    return (int.tryParse(s) ?? -1).clamp(0, maxLevel);
  }
}
