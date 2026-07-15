import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dialogs_list_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'dialog_tile.dart';
import 'filter_tabs.dart';
import 'sidebar_header.dart';

/// Левая панель: список диалогов со всеми элементами управления.
class DialogsSidebar extends StatelessWidget {
  const DialogsSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final dialogs = state.dialogs;

    return Container(
      color: p.bg1,
      child: Column(
        children: [
          const SidebarHeader(),
          if (state.connectionStatus == ConnectionStatus.error)
            _ErrorBanner(
              message: state.connectionError ?? 'Ошибка подключения',
              onRetry: () => context.read<AppState>().retryConnection(),
            ),
          const SizedBox(height: 6),
          const FilterTabs(),
          const SizedBox(height: 4),
          Divider(height: 1, color: p.border1),
          Expanded(
            child: _buildBody(context, state, p, dialogs),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppState state,
    ForumPalette p,
    List<DialogsListViewModel> dialogs,
  ) {
    if (state.isLoading && state.connectionStatus != ConnectionStatus.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: p.purple),
            const SizedBox(height: 16),
            Text(
              'Подключение к серверу…',
              style: TextStyle(color: p.text2, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (dialogs.isEmpty) {
      return Center(
        child: Text(
          state.connectionStatus == ConnectionStatus.connected
              ? 'Чаты не найдены'
              : 'Нет данных',
          style: TextStyle(color: p.text2, fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: dialogs.length,
      itemBuilder: (context, index) {
        final d = dialogs[index];
        return DialogTile(
          dialog: d,
          selected: d.id == state.selectedId,
          onTap: () => context.read<AppState>().selectDialog(d.id),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: p.text1, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}
