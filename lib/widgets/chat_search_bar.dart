import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Панель поиска по сообщениям в шапке чата.
class ChatSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loadingMore;
  final int matchCount;
  final int matchIndex;
  final VoidCallback onClose;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const ChatSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loadingMore,
    required this.matchCount,
    required this.matchIndex,
    required this.onClose,
    required this.onQueryChanged,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  String get _counterLabel {
    if (widget.matchCount <= 0) {
      return widget.loadingMore ? '…' : '0';
    }
    final current = widget.matchIndex.clamp(0, widget.matchCount - 1) + 1;
    return '$current/${widget.matchCount}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasQuery = widget.controller.text.trim().isNotEmpty;
    final canNavigate = widget.matchCount > 0;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: p.bg1,
        border: Border(bottom: BorderSide(color: p.border1)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Закрыть поиск',
            onPressed: widget.onClose,
            icon: Icon(Icons.arrow_back, color: p.text1),
          ),
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: p.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                onChanged: widget.onQueryChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: widget.onQueryChanged,
                style: TextStyle(color: p.text1, fontSize: 15),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  prefixIcon: Icon(Icons.search, color: p.text2, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 36),
                  hintText: 'Поиск',
                  hintStyle: TextStyle(color: p.text2, fontSize: 15),
                  border: InputBorder.none,
                  suffixIcon: hasQuery
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip: 'Очистить',
                          onPressed: () {
                            widget.controller.clear();
                            widget.onQueryChanged('');
                          },
                          icon: Icon(Icons.close, color: p.lime, size: 18),
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.loadingMore)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.purple,
                ),
              ),
            ),
          SizedBox(
            width: 44,
            child: Text(
              _counterLabel,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text2, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Предыдущее',
            onPressed: canNavigate ? widget.onPrevious : null,
            icon: Icon(
              Icons.keyboard_arrow_up_rounded,
              color: canNavigate ? p.text1 : p.text3,
              size: 26,
            ),
          ),
          IconButton(
            tooltip: 'Следующее',
            onPressed: canNavigate ? widget.onNext : null,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: canNavigate ? p.text1 : p.text3,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}
