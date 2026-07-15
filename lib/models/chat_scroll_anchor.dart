/// Сохранённая позиция прокрутки чата.
class ChatScrollAnchor {
  final double pixels;
  final double maxExtent;
  /// id или hash верхнего видимого сообщения (предпочтительный якорь).
  final String? messageRef;
  /// На сколько px ниже верха сообщения находится верх viewport.
  final double offsetFromTop;

  const ChatScrollAnchor({
    required this.pixels,
    required this.maxExtent,
    this.messageRef,
    this.offsetFromTop = 0,
  });

  bool get hasMessageRef =>
      messageRef != null && messageRef!.trim().isNotEmpty;

  double targetForExtent(double newMaxExtent) {
    if (newMaxExtent <= 0) return 0;
    if (maxExtent <= 0) return pixels.clamp(0, newMaxExtent);
    final ratio = pixels / maxExtent;
    return (ratio * newMaxExtent).clamp(0.0, newMaxExtent);
  }

  /// Средняя высота строки (сообщение + дата) для оценки offset до layout.
  static const double avgItemExtent = 78;

  bool get isUsable =>
      hasMessageRef || pixels > 0 || maxExtent > 0;

  /// Приблизительный offset до первого кадра (по числу строк в списке).
  double estimatedOffsetForItemCount(int itemCount) {
    if (itemCount <= 0) return 0;
    final estimatedMax = itemCount * avgItemExtent;
    return targetForExtent(estimatedMax);
  }

  Map<String, dynamic> toJson() => {
        'pixels': pixels,
        'maxExtent': maxExtent,
        if (messageRef != null && messageRef!.trim().isNotEmpty)
          'messageRef': messageRef,
        if (offsetFromTop != 0) 'offsetFromTop': offsetFromTop,
      };

  factory ChatScrollAnchor.fromJson(Map<String, dynamic> json) {
    return ChatScrollAnchor(
      pixels: (json['pixels'] as num?)?.toDouble() ?? 0,
      maxExtent: (json['maxExtent'] as num?)?.toDouble() ?? 0,
      messageRef: json['messageRef']?.toString(),
      offsetFromTop: (json['offsetFromTop'] as num?)?.toDouble() ?? 0,
    );
  }
}
