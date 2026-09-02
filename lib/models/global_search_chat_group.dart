import 'dialogs_list_view_model.dart';
import 'global_search_hit.dart';
import 'global_search_scope.dart';

/// Чаты с совпадениями глобального медиа-поиска (как в Telegram).
class GlobalSearchChatGroup {
  final DialogsListViewModel dialog;
  final List<GlobalSearchHit> hits;

  const GlobalSearchChatGroup({
    required this.dialog,
    required this.hits,
  });

  String get dialogId => dialog.id?.trim() ?? '';

  int get count => hits.length;

  String countLabel(GlobalSearchScope scope) {
    final n = count;
    return switch (scope) {
      GlobalSearchScope.photos => _plural(n, 'фото', 'фото', 'фото'),
      GlobalSearchScope.videos => _plural(n, 'видео', 'видео', 'видео'),
      GlobalSearchScope.files => _plural(n, 'файл', 'файла', 'файлов'),
      GlobalSearchScope.voice =>
        _plural(n, 'голосовое', 'голосовых', 'голосовых'),
      GlobalSearchScope.chats => '$n',
    };
  }

  static String _plural(int n, String one, String few, String many) {
    final abs = n.abs() % 100;
    final last = abs % 10;
    final word = (abs > 10 && abs < 20)
        ? many
        : (last == 1)
            ? one
            : (last >= 2 && last <= 4)
                ? few
                : many;
    return '$n $word';
  }
}
