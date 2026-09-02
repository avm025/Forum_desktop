import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/global_search_scope.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Лента категорий глобального поиска: Чаты, Фото, Видео, …
class GlobalSearchScopeRibbon extends StatelessWidget {
  const GlobalSearchScopeRibbon({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.globalSearchRibbonVisible) return const SizedBox.shrink();

    final p = context.palette;
    const scopes = GlobalSearchScope.values;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: scopes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final scope = scopes[index];
          final selected = state.globalSearchScope == scope;
          return InkWell(
            onTap: () => context.read<AppState>().setGlobalSearchScope(scope),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? p.lime.withValues(alpha: 0.15) : p.bg2,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(color: p.lime.withValues(alpha: 0.45))
                    : null,
              ),
              child: Text(
                scope.label,
                style: TextStyle(
                  color: selected ? p.lime : p.text2,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
