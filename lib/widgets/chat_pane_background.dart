import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Фон панели сообщений (выбранные обои / цвет темы).
class ChatPaneBackground extends StatelessWidget {
  final Widget? child;

  const ChatPaneBackground({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final bgUrl = state.chatBackgroundUrl(isDark: state.isDark);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: p.bg1),
        if (bgUrl != null)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: bgUrl,
              httpHeaders: ApiConfig.fileHeaders,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              // Без «иконки-плейсхолдера» — только тихий цвет темы, пока файл
              // подтянется из кэша/сети.
              placeholder: (_, __) => const SizedBox.expand(),
              errorWidget: (_, __, ___) => const SizedBox.expand(),
            ),
          ),
        if (child != null) child!,
      ],
    );
  }
}
