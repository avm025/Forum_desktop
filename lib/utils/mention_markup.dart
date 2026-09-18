import '../models/dlg_info_member.dart';

/// Упоминания в тексте сообщения (`msg.md` MarkdownV2 / plain @).
class MentionMarkup {
  MentionMarkup._();

  static final _allPlain = RegExp(
    r'(^|[\s(,])@(?:all|все|всем)(?=$|[\s,).!?])',
    caseSensitive: false,
  );

  static final _allLink = RegExp(
    r'4um://profile\?usr_id=all',
    caseSensitive: false,
  );

  static final _onlinePlain = RegExp(
    r'(^|[\s(,])@(?:online|онлайн)(?=$|[\s,).!?])',
    caseSensitive: false,
  );

  /// Активный запрос `@…` у каретки (как Telegram Desktop).
  static final activeQueryPattern = RegExp(
    r'(^|[\s(\[{«"„])@([^\s@]*)$',
    unicode: true,
  );

  /// Экстренное оповещение: `@all` / `@все` / `@всем` (в т.ч. ссылка usr_id=all).
  static bool isEmergencyAllMention(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return _allPlain.hasMatch(t) || _allLink.hasMatch(t);
  }

  static bool isOnlineMention(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return _onlinePlain.hasMatch(t) ||
        t.toLowerCase().contains('usr_id=online');
  }

  /// MarkdownV2-упоминание для `msg.body`.
  static String encodeLink({
    required String label,
    required String usrId,
  }) {
    final safeLabel = label.trim().replaceAll(RegExp(r'[\[\]]'), '');
    final display = safeLabel.isEmpty ? usrId : safeLabel;
    return '[@$display](4um://profile?usr_id=$usrId)';
  }

  /// Паттерн MarkdownV2-упоминания в `body`.
  static final mdMentionPattern = RegExp(
    r'\[@([^\]]*)\]\(4um://profile\?usr_id=([^)]+)\)',
    caseSensitive: false,
  );

  /// UI: `[@amv](4um://profile?usr_id=…)` → `@amv`.
  ///
  /// В wire остаётся MarkdownV2; в пузыре / превью — `@ник` (или label).
  static String toDisplayText(
    String text, {
    String? Function(String usrId)? nameForUserId,
  }) {
    if (text.isEmpty || !text.contains('4um://profile')) return text;
    return text.replaceAllMapped(mdMentionPattern, (m) {
      final label = (m.group(1) ?? '').trim();
      final id = (m.group(2) ?? '').trim();
      final nick = label.isNotEmpty ? label : id;
      return '@$nick';
    });
  }

  /// Заменить выбранные `@label` на MarkdownV2 перед отправкой.
  ///
  /// [tokens]: ключ — видимый токен (`@nick`), значение — `usr_id`.
  static String applyTokens(String text, Map<String, String> tokens) {
    if (text.isEmpty || tokens.isEmpty) return text;
    final keys = tokens.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var out = text;
    for (final key in keys) {
      final id = tokens[key];
      if (id == null || id.isEmpty) continue;
      final label = key.startsWith('@') ? key.substring(1) : key;
      final wireLabel = label.split(RegExp(r'\s+')).firstWhere(
            (s) => s.isNotEmpty,
            orElse: () => label,
          );
      final encoded = encodeLink(label: wireLabel, usrId: id);
      out = out.replaceAllMapped(
        RegExp('${RegExp.escape(key)}(?=\$|[\\s,).!?])'),
        (_) => encoded,
      );
    }
    return out;
  }
}

/// Кандидат в списке упоминаний (участник или спец. `@all` / `@online`).
class MentionCandidate {
  final String usrId;
  final String title;
  final String subtitle;
  final String avatar;
  final int colAvaId;
  final bool online;
  final bool special;

  const MentionCandidate({
    required this.usrId,
    required this.title,
    this.subtitle = '',
    this.avatar = '',
    this.colAvaId = 1,
    this.online = false,
    this.special = false,
  });

  /// Текст, который виден в поле ввода после выбора (`@amv`).
  String get insertLabel {
    if (special) return title.startsWith('@') ? title.substring(1) : title;
    final nick = subtitle.startsWith('@') ? subtitle.substring(1) : subtitle;
    if (nick.isNotEmpty) return nick;
    return title.trim().isNotEmpty ? title.trim() : usrId;
  }

  static List<MentionCandidate> filter({
    required List<DlgInfoMember> members,
    required String query,
  }) {
    final q = query.trim().toLowerCase();
    final out = <MentionCandidate>[];

    void addSpecial({
      required String id,
      required String title,
      required String subtitle,
      required List<String> aliases,
    }) {
      if (q.isNotEmpty &&
          !aliases.any((a) {
            final al = a.toLowerCase();
            return al.startsWith(q) || al.contains(q);
          })) {
        return;
      }
      out.add(MentionCandidate(
        usrId: id,
        title: title,
        subtitle: subtitle,
        special: true,
      ));
    }

    addSpecial(
      id: 'all',
      title: 'all',
      subtitle: 'Уведомить всех',
      aliases: const ['all', 'все', 'всем'],
    );
    addSpecial(
      id: 'online',
      title: 'online',
      subtitle: 'Кто сейчас в сети',
      aliases: const ['online', 'онлайн'],
    );

    for (final m in members) {
      final name = m.name.trim();
      final nick = m.nick.trim().replaceFirst(RegExp(r'^@'), '');
      final phone = m.phone.trim();
      if (q.isNotEmpty) {
        final hay = '$name $nick $phone ${m.id}'.toLowerCase();
        if (!hay.contains(q) &&
            !name.toLowerCase().startsWith(q) &&
            !nick.toLowerCase().startsWith(q) &&
            !phone.contains(q)) {
          continue;
        }
      }
      out.add(MentionCandidate(
        usrId: m.id,
        title: name.isNotEmpty ? name : (nick.isNotEmpty ? nick : m.id),
        subtitle: nick.isNotEmpty ? '@$nick' : '',
        avatar: '', // без сети — иначе dispose картинок вешает курсор
        colAvaId: m.colAvaId,
        online: m.online,
      ));
    }

    final specials = out.where((c) => c.special).toList();
    final people = out.where((c) => !c.special).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [...specials, ...people];
  }
}

/// Активный фрагмент `@query` в композере.
class MentionQuery {
  final int atIndex;
  final String query;

  const MentionQuery({required this.atIndex, required this.query});

  static MentionQuery? atCaret(String text, int caret) {
    if (caret < 0 || caret > text.length) return null;
    final before = text.substring(0, caret);
    final m = MentionMarkup.activeQueryPattern.firstMatch(before);
    if (m == null) return null;
    final atPos = before.lastIndexOf('@');
    if (atPos < 0) return null;
    return MentionQuery(atIndex: atPos, query: m.group(2) ?? '');
  }
}
