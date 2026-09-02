import 'package:flutter/material.dart';

/// Управление поиском внутри открытого чата (шапка, профиль).
class ChatSearchScope extends InheritedWidget {
  const ChatSearchScope({
    super.key,
    required this.openSearch,
    required this.closeSearch,
    required this.isOpen,
    required super.child,
  });

  final VoidCallback openSearch;
  final VoidCallback closeSearch;
  final bool isOpen;

  static ChatSearchScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatSearchScope>();
  }

  @override
  bool updateShouldNotify(ChatSearchScope oldWidget) =>
      oldWidget.isOpen != isOpen ||
      oldWidget.openSearch != openSearch ||
      oldWidget.closeSearch != closeSearch;
}
