import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'create_chat_menu.dart';

/// Шапка списка чатов: меню, заголовок "Чаты", кнопка создания.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Icon(Icons.dehaze_rounded, color: p.purple, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
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
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
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

class _SearchField extends StatelessWidget {
  final ForumPalette palette;
  const _SearchField({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: palette.bg2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        onChanged: context.read<AppState>().setSearch,
        style: TextStyle(color: palette.text1, fontSize: 15),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: Icon(Icons.search, color: palette.text2, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 36),
          hintText: 'Поиск',
          hintStyle: TextStyle(color: palette.text2, fontSize: 15),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
