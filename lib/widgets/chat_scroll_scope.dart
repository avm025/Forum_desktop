import 'package:flutter/material.dart';

/// Действия прокрутки внутри открытого чата (переход к цитируемому сообщению).
class ChatScrollScope extends InheritedWidget {
  const ChatScrollScope({
    super.key,
    required this.scrollToMessage,
    required super.child,
  });

  final Future<void> Function(String messageId) scrollToMessage;

  static ChatScrollScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatScrollScope>();
  }

  @override
  bool updateShouldNotify(ChatScrollScope oldWidget) =>
      oldWidget.scrollToMessage != scrollToMessage;
}
