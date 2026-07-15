import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_logger.dart';
import '../theme/app_theme.dart';

/// Экран лога API — показывается на вкладке «Новое».
class ApiLogScreen extends StatefulWidget {
  const ApiLogScreen({super.key});

  @override
  State<ApiLogScreen> createState() => _ApiLogScreenState();
}

class _ApiLogScreenState extends State<ApiLogScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final logger = context.watch<ApiLogger>();
    final p = context.palette;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());

    return Container(
      color: p.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text(
                  'Лог API',
                  style: TextStyle(
                    color: p.text1,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => logger.clear(),
                  child: const Text('Очистить'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'forum_api.log — запросы и ответы с меткой времени старта',
              style: TextStyle(color: p.text2, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logger.content.isEmpty
                ? Center(
                    child: Text(
                      'Пока нет записей.\nПодключитесь к серверу и откройте чаты.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.text2, fontSize: 14),
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    decoration: BoxDecoration(
                      color: p.bg2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.border1),
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          logger.content,
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
