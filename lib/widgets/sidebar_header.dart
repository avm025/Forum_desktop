import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'create_chat_menu.dart';

/// Шапка списка чатов: меню выбора, заголовок "Чаты", кнопка создания.
class SidebarHeader extends StatefulWidget {
  const SidebarHeader({super.key});

  @override
  State<SidebarHeader> createState() => _SidebarHeaderState();
}

class _SidebarHeaderState extends State<SidebarHeader> {
  final _createButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final selectMode = state.dialogsSelectMode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                if (selectMode)
                  TextButton(
                    onPressed: () =>
                        context.read<AppState>().exitDialogsSelectMode(),
                    style: TextButton.styleFrom(
                      foregroundColor: p.purple,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Готово',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: 'Выбрать чаты',
                    onPressed: () =>
                        context.read<AppState>().toggleDialogsSelectMode(),
                    icon: Icon(
                      Icons.format_list_bulleted_rounded,
                      color: p.purple,
                      size: 26,
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: selectMode
                      ? const SizedBox.shrink()
                      : Text(
                          'Чаты',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                if (!selectMode) ...[
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 36),
                    tooltip: state.isDark ? 'Светлая тема' : 'Тёмная тема',
                    onPressed: context.read<AppState>().toggleTheme,
                    icon: Icon(
                      state.isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: p.text2,
                      size: 22,
                    ),
                  ),
                  _CreateButton(
                    key: _createButtonKey,
                    onPressed: () =>
                        CreateChatMenu.open(context, _createButtonKey),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SearchField(palette: p),
        ],
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CreateButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Material(
      color: p.purple,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.edit_outlined,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  final ForumPalette palette;

  const _SearchField({required this.palette});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final initial = context.read<AppState>().search;
    _controller = TextEditingController(text: initial);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openRibbon() {
    context.read<AppState>().openGlobalSearchRibbon();
  }

  void _syncFromState(String search) {
    if (_controller.text == search) return;
    _controller.value = TextEditingValue(
      text: search,
      selection: TextSelection.collapsed(offset: search.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final search = state.search;
    if (_controller.text != search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncFromState(context.read<AppState>().search);
      });
    }

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: widget.palette.bg2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onTap: _openRibbon,
        onChanged: context.read<AppState>().setSearch,
        style: TextStyle(color: widget.palette.text1, fontSize: 15),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: GestureDetector(
            onTap: () {
              _openRibbon();
              _focusNode.requestFocus();
            },
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.search, color: widget.palette.text2, size: 18),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 36),
          hintText: 'Поиск',
          hintStyle: TextStyle(color: widget.palette.text2, fontSize: 15),
          border: InputBorder.none,
          suffixIcon: search.isNotEmpty
              ? IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(Icons.close, color: widget.palette.text2, size: 18),
                  onPressed: () {
                    _controller.clear();
                    context.read<AppState>().setSearch('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}
