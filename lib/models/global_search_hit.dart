import 'global_search_scope.dart';
import 'dialogs_list_view_model.dart';
import 'media_file.dart';
import 'message_view_model.dart';

/// Результат глобального поиска по медиа/голосовым в ленте чатов.
class GlobalSearchHit {
  final GlobalSearchScope scope;
  final DialogsListViewModel dialog;
  final MessageViewModel message;
  final MediaFile? file;
  final String title;
  final String subtitle;

  const GlobalSearchHit({
    required this.scope,
    required this.dialog,
    required this.message,
    this.file,
    required this.title,
    required this.subtitle,
  });

  String get dialogId => dialog.id?.trim() ?? '';
  String get messageRef => message.referenceId;

  /// Уникальный ключ результата (чат + сообщение + файл).
  String get selectionKey {
    final f = file;
    final fileKey = f == null
        ? 'nofile'
        : [
            f.hash.trim(),
            f.fname.trim(),
            f.url.trim(),
            f.title.trim(),
          ].join('|');
    return '$dialogId::$messageRef::$fileKey::$title';
  }
}
