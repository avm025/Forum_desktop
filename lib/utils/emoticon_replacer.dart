import 'dart:convert';

/// Замена текстовых смайлов (`:)`, `;-)` и т.д.) на эмодзи при отправке.
///
/// Не трогает JSON/HTML, URL и другие структурированные фрагменты.
class EmoticonReplacer {
  EmoticonReplacer._();

  static const Map<String, String> _replacements = {
    ':-)': '🙂',
    ':)': '🙂',
    ':-(': '🙁',
    ':(': '🙁',
    ';-)': '😉',
    ';)': '😉',
    ':-D': '😄',
    ':D': '😄',
    ':-d': '😄',
    ':d': '😄',
    ':-P': '😛',
    ':P': '😛',
    ':-p': '😛',
    ':p': '😛',
    ':-O': '😮',
    ':O': '😮',
    ':-o': '😮',
    ':o': '😮',
    ":'(": '😢',
    ":'-(": '😢',
    ':-*': '😘',
    ':*': '😘',
    '<3': '❤️',
    '</3': '💔',
    ':-/': '😕',
    ':/': '😕',
    ':-\\': '😕',
    ':\\': '😕',
    ':-|': '😐',
    ':|': '😐',
    'B-)': '😎',
    'B)': '😎',
    'O:)': '😇',
    'O:-)': '😇',
    '>:(': '😠',
    '>:-(': '😠',
    ":'D": '😂',
    ':-]': '😊',
    ':]': '😊',
  };

  static final _root = _buildTrie(_replacements);

  /// Символы, с которых может начинаться смайл — быстрый пропуск текста без них.
  static final Set<int> _triggers = _root.children.keys.toSet();

  static final RegExp _urlPattern = RegExp(
    r'(?:https?://|www\.|ftp://)[^\s<>"{}|\\^`\[\]]+|'
    r'[a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static final RegExp _htmlTagPattern = RegExp(r'<[^>]+>');

  /// Заменяет известные смайлы в обычном тексте. JSON/HTML/URL не изменяются.
  static String replace(String text) {
    if (text.isEmpty) return text;

    var hasTrigger = false;
    for (var i = 0; i < text.length; i++) {
      if (_triggers.contains(text.codeUnitAt(i))) {
        hasTrigger = true;
        break;
      }
    }
    if (!hasTrigger) return text;
    if (_looksLikeStructuredPayload(text)) return text;

    final protected = _mergeRanges([
      ..._urlRanges(text),
      ..._htmlTagRanges(text),
    ]);

    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      if (_inRanges(i, protected)) {
        final end = _rangeEnd(i, protected);
        out.write(text.substring(i, end));
        i = end;
        continue;
      }

      final code = text.codeUnitAt(i);
      if (_triggers.contains(code)) {
        final match = _match(text, i);
        if (match != null &&
            !_inRanges(i, protected) &&
            _canReplaceAt(text, i, match.$2)) {
          out.write(match.$1);
          i += match.$2;
          continue;
        }
      }
      out.writeCharCode(code);
      i++;
    }
    return out.toString();
  }

  /// Целиком JSON/HTML — не обрабатываем.
  static bool _looksLikeStructuredPayload(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        jsonDecode(trimmed);
        return true;
      } catch (_) {}
    }

    if (_htmlTagPattern.hasMatch(trimmed) &&
        !RegExp(r'<\d').hasMatch(trimmed)) {
      final withoutTags = trimmed.replaceAll(_htmlTagPattern, '').trim();
      if (withoutTags.isEmpty || withoutTags.length < trimmed.length * 0.35) {
        return true;
      }
    }

    return false;
  }

  static List<(int start, int end)> _urlRanges(String text) {
    return _urlPattern
        .allMatches(text)
        .map((m) => (m.start, m.end))
        .toList();
  }

  static List<(int start, int end)> _htmlTagRanges(String text) {
    return _htmlTagPattern
        .allMatches(text)
        .map((m) => (m.start, m.end))
        .toList();
  }

  static List<(int start, int end)> _mergeRanges(List<(int, int)> ranges) {
    if (ranges.isEmpty) return const [];
    final sorted = List<(int, int)>.from(ranges)
      ..sort((a, b) => a.$1.compareTo(b.$1));

    final merged = <(int, int)>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;
      if (current.$1 <= last.$2) {
        merged[merged.length - 1] = (last.$1, current.$2 > last.$2 ? current.$2 : last.$2);
      } else {
        merged.add(current);
      }
    }
    return merged;
  }

  static bool _inRanges(int index, List<(int, int)> ranges) {
    for (final range in ranges) {
      if (index >= range.$1 && index < range.$2) return true;
    }
    return false;
  }

  static int _rangeEnd(int index, List<(int, int)> ranges) {
    for (final range in ranges) {
      if (index >= range.$1 && index < range.$2) return range.$2;
    }
    return index + 1;
  }

  /// Контекстные ограничения, чтобы не ломать URL и HTML-теги.
  static bool _canReplaceAt(String text, int start, int length) {
    final snippet = text.substring(start, start + length);
    final first = snippet.codeUnitAt(0);

    if (first == 0x3a || first == 0x3b) {
      // ':' или ';' — не внутри URL/host:port и не после буквы/цифры.
      if (start > 0) {
        final prev = text.codeUnitAt(start - 1);
        if (_isIdentifierChar(prev) || prev == 0x2f) return false;
      }
    }

    if (first == 0x3c) {
      // '<' — только отдельные паттерны (<3, </3), не часть тега.
      if (snippet.startsWith('</')) {
        final nextIndex = start + length;
        if (nextIndex < text.length) {
          final next = text.codeUnitAt(nextIndex);
          if (_isIdentifierChar(next)) return false;
        }
      }
    }

    if (start > 0 && text.codeUnitAt(start - 1) == 0x3c) {
      return false;
    }

    return true;
  }

  static bool _isIdentifierChar(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        codeUnit == 0x5f ||
        codeUnit == 0x2d;
  }

  static (String emoji, int length)? _match(String text, int start) {
    var node = _root;
    (String, int)? best;

    for (var i = start; i < text.length; i++) {
      final next = node.children[text.codeUnitAt(i)];
      if (next == null) break;
      node = next;
      if (node.emoji != null) {
        best = (node.emoji!, i - start + 1);
      }
    }
    return best;
  }

  static _TrieNode _buildTrie(Map<String, String> map) {
    final root = _TrieNode();
    for (final entry in map.entries) {
      var node = root;
      for (final unit in entry.key.codeUnits) {
        node = node.children.putIfAbsent(unit, () => _TrieNode());
      }
      node.emoji = entry.value;
    }
    return root;
  }
}

class _TrieNode {
  final Map<int, _TrieNode> children = {};
  String? emoji;
}
