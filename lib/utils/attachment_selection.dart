import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Глобальное выделение вложений: один «владелец» на всё окно чата.
class AttachmentSelection {
  AttachmentSelection._();

  /// Текущий виджет с выделением (MediaGrid / DocumentAttachmentList).
  static final ValueNotifier<Object?> activeOwner = ValueNotifier<Object?>(null);

  static final ValueNotifier<int> clearToken = ValueNotifier<int>(0);
  static bool _retainPointer = false;
  static bool _keyboardBound = false;

  static void ensureKeyboardBound() {
    if (_keyboardBound) return;
    _keyboardBound = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      clear();
    }
    return false;
  }

  /// Pointer down по вложениям — не сбрасывать через clearIfOutside.
  static void retainPointer() => _retainPointer = true;

  /// Сделать [owner] единственным владельцем выделения (остальные сбрасывают).
  static void claim(Object owner) {
    if (identical(activeOwner.value, owner)) return;
    activeOwner.value = owner;
  }

  static void clear() {
    _retainPointer = false;
    activeOwner.value = null;
    clearToken.value++;
  }

  /// Клик по ленте / пустой области: сброс, если не попали во вложения.
  static void clearIfOutside() {
    if (_retainPointer) {
      _retainPointer = false;
      return;
    }
    clear();
  }
}
