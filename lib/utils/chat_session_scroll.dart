import '../state/app_state.dart';

/// Позиции скролла чатов в текущей сессии (без IndexedStack).
class ChatSessionScroll {
  ChatSessionScroll._();

  static final Map<String, double> _pixels = {};
  static final Set<String> _opened = {};

  static String _key(String dlgId) => dlgId.trim();

  static bool wasOpened(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return false;
    final key = _key(dlgId);
    if (_opened.contains(key)) return true;
    return _opened.any((id) => AppState.dlgIdsEqual(id, dlgId));
  }

  static void markOpened(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return;
    _opened.add(_key(dlgId));
  }

  static double? pixels(String? dlgId) {
    if (dlgId == null || dlgId.trim().isEmpty) return null;
    final key = _key(dlgId);
    final direct = _pixels[key];
    if (direct != null) return direct;
    for (final e in _pixels.entries) {
      if (AppState.dlgIdsEqual(e.key, dlgId)) return e.value;
    }
    return null;
  }

  static void save(String? dlgId, double pixels) {
    if (dlgId == null || dlgId.trim().isEmpty) return;
    if (pixels.isNaN) return;
    _pixels[_key(dlgId)] = pixels;
    markOpened(dlgId);
  }
}
