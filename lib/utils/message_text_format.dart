import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

import 'chat_message_search.dart';

/// Форматирование текста сообщения: Markdown (`**`, `*`, `[text](url)`) и HTML `<a>`.
class MessageTextFormat {
  MessageTextFormat._();

  static final _htmlAnchor = RegExp(
    r'''<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  static final _mdLink = RegExp(
    r'\[([^\]]+)\]\((https?://[^)\s]+)\)',
    caseSensitive: false,
  );

  static final _bareUrl = RegExp(
    r'(?:https?://|www\.)[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static final _htmlTag = RegExp(r'<[^>]+>');

  /// Текст без разметки (для выделения / копирования / поиска).
  static String plain(String raw) => _parse(raw).plain;

  /// Стилизованные spans. [recognizers] нужно dispose в State.
  static TextSpan rich({
    required String raw,
    required TextStyle style,
    required Color linkColor,
    required List<TapGestureRecognizer> recognizers,
    required void Function(String url) onLinkTap,
    String? searchQuery,
    Color? highlightColor,
  }) {
    final parsed = _parse(raw);
    final children = <InlineSpan>[];
    for (final run in parsed.runs) {
      var runStyle = style;
      if (run.bold) {
        runStyle = runStyle.copyWith(fontWeight: FontWeight.w700);
      }
      if (run.italic) {
        runStyle = runStyle.copyWith(fontStyle: FontStyle.italic);
      }
      if (run.link != null) {
        final url = run.link!;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onLinkTap(url);
        recognizers.add(recognizer);
        runStyle = runStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        );
        children.addAll(
          _highlighted(
            run.text,
            runStyle,
            searchQuery: searchQuery,
            highlightColor: highlightColor,
            recognizer: recognizer,
          ),
        );
      } else {
        children.addAll(
          _highlighted(
            run.text,
            runStyle,
            searchQuery: searchQuery,
            highlightColor: highlightColor,
          ),
        );
      }
    }
    return TextSpan(style: style, children: children);
  }

  static List<InlineSpan> _highlighted(
    String text,
    TextStyle style, {
    String? searchQuery,
    Color? highlightColor,
    GestureRecognizer? recognizer,
  }) {
    final query = searchQuery?.trim();
    if (query == null || query.isEmpty || highlightColor == null) {
      return [
        TextSpan(text: text, style: style, recognizer: recognizer),
      ];
    }
    final parts = ChatMessageSearch.highlightParts(text, query);
    return [
      for (final part in parts)
        TextSpan(
          text: part.text,
          style: style.copyWith(
            backgroundColor: part.match ? highlightColor : null,
          ),
          recognizer: recognizer,
        ),
    ];
  }

  static _Parsed _parse(String raw) {
    if (raw.isEmpty) return const _Parsed('', []);

    // 1) HTML <a href> → markdown-ссылки, остальные теги убрать.
    var text = raw.replaceAllMapped(_htmlAnchor, (m) {
      final href = _unescapeHtml(m.group(1) ?? '').trim();
      final label = _stripTags(_unescapeHtml(m.group(2) ?? '')).trim();
      if (href.isEmpty) return label;
      final shown = label.isEmpty ? href : label;
      return '[$shown]($href)';
    });
    text = text.replaceAllMapped(_htmlTag, (m) {
      final tag = m.group(0)!.toLowerCase();
      if (tag == '<br>' || tag == '<br/>' || tag == '<br />') return '\n';
      return '';
    });
    text = _unescapeHtml(text);

    final runs = <_Run>[];
    _emitMarkdown(text, runs, bold: false, italic: false);
    final plainBuf = StringBuffer();
    for (final r in runs) {
      plainBuf.write(r.text);
    }
    return _Parsed(plainBuf.toString(), runs);
  }

  static void _emitMarkdown(
    String text,
    List<_Run> out, {
    required bool bold,
    required bool italic,
  }) {
    var i = 0;
    while (i < text.length) {
      // **bold**
      if (text.startsWith('**', i)) {
        final close = text.indexOf('**', i + 2);
        if (close > i + 2) {
          _emitMarkdown(
            text.substring(i + 2, close),
            out,
            bold: true,
            italic: italic,
          );
          i = close + 2;
          continue;
        }
      }

      // *italic* (не часть **)
      if (text[i] == '*' && !text.startsWith('**', i)) {
        final close = _findSingleStarClose(text, i + 1);
        if (close != null) {
          _emitMarkdown(
            text.substring(i + 1, close),
            out,
            bold: bold,
            italic: true,
          );
          i = close + 1;
          continue;
        }
      }

      // [label](https://…)
      if (text[i] == '[') {
        final m = _mdLink.matchAsPrefix(text, i);
        if (m != null) {
          final label = m.group(1) ?? '';
          final url = m.group(2) ?? '';
          if (label.isNotEmpty && url.isNotEmpty) {
            _appendRun(out, label, bold: bold, italic: italic, link: url);
            i = m.end;
            continue;
          }
        }
      }

      // bare URL
      final urlMatch = _bareUrl.matchAsPrefix(text, i);
      if (urlMatch != null) {
        var url = urlMatch.group(0)!;
        // обрезать хвостовую пунктуацию
        while (url.isNotEmpty && '.,);]»"\''.contains(url[url.length - 1])) {
          url = url.substring(0, url.length - 1);
        }
        if (url.length >= 8) {
          final href = url.startsWith('www.') ? 'https://$url' : url;
          _appendRun(out, url, bold: bold, italic: italic, link: href);
          i += url.length;
          continue;
        }
      }

      // plain chunk до следующего маркера
      final next = _nextMarker(text, i + 1);
      _appendRun(
        out,
        text.substring(i, next),
        bold: bold,
        italic: italic,
      );
      i = next;
    }
  }

  static int? _findSingleStarClose(String text, int from) {
    for (var j = from; j < text.length; j++) {
      if (text[j] != '*') continue;
      if (text.startsWith('**', j)) {
        j++; // skip
        continue;
      }
      if (j > from) return j;
    }
    return null;
  }

  static int _nextMarker(String text, int from) {
    for (var i = from; i < text.length; i++) {
      final c = text[i];
      if (c == '*' || c == '[') return i;
      if (c == 'h' || c == 'H' || c == 'w' || c == 'W') {
        if (_bareUrl.matchAsPrefix(text, i) != null) return i;
      }
    }
    return text.length;
  }

  static void _appendRun(
    List<_Run> out,
    String text, {
    required bool bold,
    required bool italic,
    String? link,
  }) {
    if (text.isEmpty) return;
    if (out.isNotEmpty) {
      final last = out.last;
      if (last.bold == bold &&
          last.italic == italic &&
          last.link == link) {
        out[out.length - 1] = _Run(
          last.text + text,
          bold: bold,
          italic: italic,
          link: link,
        );
        return;
      }
    }
    out.add(_Run(text, bold: bold, italic: italic, link: link));
  }

  static String _stripTags(String s) => s.replaceAll(_htmlTag, '');

  static String _unescapeHtml(String s) {
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}

class _Run {
  final String text;
  final bool bold;
  final bool italic;
  final String? link;

  const _Run(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.link,
  });
}

class _Parsed {
  final String plain;
  final List<_Run> runs;

  const _Parsed(this.plain, this.runs);
}
