/// Категория глобального поиска в списке чатов.
enum GlobalSearchScope {
  chats,
  photos,
  videos,
  files,
  voice,
}

extension GlobalSearchScopeLabel on GlobalSearchScope {
  String get label => switch (this) {
        GlobalSearchScope.chats => 'Чаты',
        GlobalSearchScope.photos => 'Фото',
        GlobalSearchScope.videos => 'Видео',
        GlobalSearchScope.files => 'Файлы',
        GlobalSearchScope.voice => 'Голосовые',
      };
}
