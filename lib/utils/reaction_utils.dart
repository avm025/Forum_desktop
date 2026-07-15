/// Утилиты сравнения реакций (emoji, usr_id).
class ReactionUtils {
  ReactionUtils._();

  static bool sameUserId(String a, String b) {
    final sa = a.trim();
    final sb = b.trim();
    if (sa.isEmpty || sb.isEmpty) return false;
    if (sa == sb) return true;
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    return na != null && nb != null && na == nb;
  }

  static String normalizeEmoji(String emoji) {
    return emoji
        .trim()
        .replaceAll('\uFE0F', '')
        .replaceAll('\u200D', '');
  }

  static bool sameEmoji(String a, String b) {
    return normalizeEmoji(a) == normalizeEmoji(b);
  }
}
