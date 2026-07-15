/// Стандартный набор реакций Telegram Desktop / MTProto.
/// Источник: core.telegram.org/api/reactions, tdesktop quick reactions.
const kTelegramReactionEmojis = [
  '👍',
  '👎',
  '❤️',
  '🔥',
  '🥰',
  '👏',
  '😁',
  '🤔',
  '🤯',
  '😱',
  '🤬',
  '😢',
  '🎉',
  '🤩',
  '🤮',
  '💩',
  '🙏',
  '👌',
  '🕊️',
  '🤡',
  '🥱',
  '🥴',
  '😍',
  '🐳',
  '❤️‍🔥',
  '🌚',
  '🌭',
  '💯',
  '🤣',
  '⚡',
  '🍌',
  '🏆',
  '💔',
  '🤨',
  '😐',
  '🍓',
  '🍾',
  '💋',
  '🖕',
  '😈',
  '😴',
  '😭',
  '🤓',
  '👻',
  '👨‍💻',
  '👀',
  '🎃',
  '🙈',
  '😇',
  '😨',
  '🤝',
  '✍️',
  '🤗',
  '🫡',
  '🎅',
  '🎄',
  '☃️',
  '💅',
  '🤪',
  '🗿',
  '🆒',
  '💘',
  '🙉',
  '🦄',
  '😘',
  '💊',
  '🙊',
  '😎',
  '👾',
  '🤷‍♂️',
  '🤷',
  '🤷‍♀️',
  '😡',
];

/// Сколько emoji в свёрнутой строке (Telegram Desktop).
const kTelegramCollapsedReactionCount = 7;

class TelegramReactions {
  TelegramReactions._();

  static final Map<String, String> _aliases = {
    for (final e in kTelegramReactionEmojis) _normalizeKey(e): e,
    '❤': '❤️',
    '🕊': '🕊️',
    '✍': '✍️',
    '☃': '☃️',
  };

  static String _normalizeKey(String emoji) =>
      emoji.replaceAll('\uFE0F', '').trim();

  static String? _canonical(String emoji) {
    final key = _normalizeKey(emoji);
    return _aliases[key] ?? (emoji.trim().isEmpty ? null : emoji.trim());
  }

  /// Серверный каталог + порядок Telegram.
  static List<String> mergeCatalog(Iterable<String> server) {
    final serverCanonical = <String>{};
    for (final raw in server) {
      final c = _canonical(raw);
      if (c != null) serverCanonical.add(c);
    }

    final result = <String>[];
    for (final emoji in kTelegramReactionEmojis) {
      if (serverCanonical.remove(emoji)) {
        result.add(emoji);
      }
    }
    result.addAll(serverCanonical);
    return result;
  }
}
