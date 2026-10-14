import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../utils/telegram_emoji_data.dart';

/// Панель emoji как в Telegram Desktop.
class TelegramEmojiPanel extends StatefulWidget {
  final ValueChanged<String> onEmoji;
  final VoidCallback? onClose;
  final double width;
  final double height;
  final bool showClose;

  const TelegramEmojiPanel({
    super.key,
    required this.onEmoji,
    this.onClose,
    this.width = 332,
    this.height = 500,
    this.showClose = true,
  });

  @override
  State<TelegramEmojiPanel> createState() => _TelegramEmojiPanelState();
}

class _TelegramEmojiPanelState extends State<TelegramEmojiPanel> {
  static const _recentKey = 'forum_emoji_recent';
  static const _cols = 8;
  static const _hPad = 8.0;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<String> _recent = [];
  String _query = '';
  int _mainTab = 0; // 0 emoji, 1 stickers, 2 gif
  int _packTab = 0; // 0 recent, 1+ categories

  static const _lockedPacks = ['🎂', '😈', '🥰', '🐱', '👻'];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? const [];
    if (!mounted) return;
    setState(() => _recent = list);
  }

  Future<void> _remember(String emoji) async {
    final next = [emoji, ..._recent.where((e) => e != emoji)].take(32).toList();
    setState(() => _recent = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, next);
  }

  void _pick(String emoji) {
    unawaited(_remember(emoji));
    widget.onEmoji(emoji);
  }

  /// Поиск по ключевым словам (рус/англ) + прямое совпадение emoji.
  List<String> _searchResults(String q) {
    final out = <String>[];
    final seen = <String>{};
    void add(String e) {
      if (seen.add(e)) out.add(e);
    }

    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    for (final w in words) {
      for (final entry in kTelegramEmojiKeywords.entries) {
        if (entry.key.startsWith(w) || w.startsWith(entry.key)) {
          entry.value.forEach(add);
        }
      }
    }
    // Если вставили сам emoji — покажем его.
    for (final c in kTelegramEmojiCategories) {
      for (final e in c.emojis) {
        if (q.contains(e)) add(e);
      }
    }
    return out;
  }

  double get _cell => (widget.width - _hPad * 2) / _cols;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final searching = _query.isNotEmpty;
    return Material(
      color: p.bg1,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_mainTab == 0 && !searching) _buildPackBar(p),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: _buildSearch(p),
            ),
            Expanded(child: _buildBody(p)),
            _buildBottomTabs(p),
          ],
        ),
      ),
    );
  }

  Widget _buildPackBar(ForumPalette p) {
    // Отступ справа больше радиуса скругления панели — иначе крайний
    // «Тортик» (🎂) обрезается clip антиалиаса у правого края.
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.border1.withValues(alpha: 0.55)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 5, 20, 5),
        children: [
          _packChip(
            p,
            selected: _packTab == 0,
            onTap: () => _selectPack(0),
            child: Icon(
              Icons.schedule_rounded,
              size: 18,
              color: _packTab == 0 ? p.text1 : p.text2,
            ),
          ),
          for (var i = 0; i < kTelegramEmojiCategories.length; i++)
            _packChip(
              p,
              selected: _packTab == i + 1,
              onTap: () => _selectPack(i + 1),
              child: Text(
                kTelegramEmojiCategories[i].icon,
                style: const TextStyle(fontSize: 17, height: 1),
              ),
            ),
          for (final pack in _lockedPacks)
            _packChip(
              p,
              selected: false,
              onTap: () {},
              locked: true,
              child: Text(pack, style: const TextStyle(fontSize: 17, height: 1)),
            ),
        ],
      ),
    );
  }

  void _selectPack(int index) {
    setState(() {
      _packTab = index;
      _query = '';
      _search.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _packChip(
    ForumPalette p, {
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    bool locked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? p.bg3 : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: child,
              ),
              if (locked)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 7,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearch(ForumPalette p) {
    final hasText = _query.isNotEmpty;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: p.bg3,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: p.text3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              style: TextStyle(color: p.text1, fontSize: 14),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Поиск',
                hintStyle: TextStyle(color: p.text3, fontSize: 14),
              ),
            ),
          ),
          if (hasText)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _search.clear(),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: p.text3,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded, size: 13, color: p.bg1),
              ),
            )
          else if (widget.showClose && widget.onClose != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: widget.onClose,
              icon: Icon(Icons.close_rounded, size: 18, color: p.text2),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ForumPalette p) {
    if (_mainTab == 1) return _placeholder(p, 'Стикеры скоро');
    if (_mainTab == 2) return _placeholder(p, 'GIF скоро');

    if (_query.isNotEmpty) {
      final results = _searchResults(_query);
      if (results.isEmpty) {
        return Center(
          child: Text('Ничего не найдено', style: TextStyle(color: p.text2)),
        );
      }
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, 6),
        children: [
          _sectionTitle(p, 'ЭМОДЗИ'),
          _emojiGrid(results),
        ],
      );
    }

    if (_packTab == 0) {
      final popular = _recent.isEmpty ? kTelegramQuickEmojis : _recent;
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, 6),
        children: [
          _emojiGrid(popular),
          for (final c in kTelegramEmojiCategories) ...[
            _sectionTitle(p, c.title),
            _emojiGrid(c.emojis),
          ],
        ],
      );
    }

    final cat = kTelegramEmojiCategories[_packTab - 1];
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, 6),
      children: [
        _sectionTitle(p, cat.title),
        _emojiGrid(cat.emojis),
      ],
    );
  }

  Widget _placeholder(ForumPalette p, String text) {
    return Center(
      child: Text(text, style: TextStyle(color: p.text2, fontSize: 14)),
    );
  }

  Widget _sectionTitle(ForumPalette p, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
      child: Text(
        title,
        style: TextStyle(
          color: p.text3,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// Сетка 8×N: смайл крупный, зазор между ними как в Telegram.
  Widget _emojiGrid(List<String> emojis) {
    final cell = _cell;
    final emojiSize = cell * 0.76;
    return SizedBox(
      width: widget.width - _hPad * 2,
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          for (final emoji in emojis)
            SizedBox(
              width: cell,
              height: cell,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _pick(emoji),
                  child: Center(
                    child: Text(
                      emoji,
                      style: TextStyle(fontSize: emojiSize, height: 1),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomTabs(ForumPalette p) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border1.withValues(alpha: 0.55)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _bottomTab(p, label: 'Эмодзи', index: 0),
          _bottomTab(p, label: 'Стикеры', index: 1),
          _bottomTab(p, label: 'GIF', index: 2),
        ],
      ),
    );
  }

  Widget _bottomTab(
    ForumPalette p, {
    required String label,
    required int index,
  }) {
    final on = _mainTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _mainTab = index;
          _query = '';
          _search.clear();
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: on ? p.bg3 : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? p.text1 : p.text2,
            fontSize: 14,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
