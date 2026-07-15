import 'telegram_reactions.dart';

/// Категория emoji из HTTP `type: emoji`.
class EmojiCategory {
  final int id;
  final String name;
  final List<EmojiItem> emojis;

  const EmojiCategory({
    required this.id,
    required this.name,
    required this.emojis,
  });

  factory EmojiCategory.fromJson(Map<String, dynamic> json) {
    final raw = json['emojis'];
    final items = <EmojiItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(EmojiItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return EmojiCategory(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      emojis: items,
    );
  }
}

class EmojiItem {
  final String emoji;
  final String? ru;
  final String? en;

  const EmojiItem({required this.emoji, this.ru, this.en});

  factory EmojiItem.fromJson(Map<String, dynamic> json) => EmojiItem(
        emoji: json['emoji']?.toString() ?? '',
        ru: json['ru']?.toString(),
        en: json['en']?.toString(),
      );
}

/// Быстрые реакции (Telegram), если HTTP-справочник недоступен.
const kDefaultQuickReactions = kTelegramReactionEmojis;
