import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/media_viewer_context.dart';

/// In-app оверлей (fallback): blur внутри окна, тап мимо — закрыть.
class TelegramMediaOverlay {
  TelegramMediaOverlay._();

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool coverDisplay = false,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.transparent,
      useRootNavigator: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return builder(ctx);
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }
}

/// Оболочка: blur; тап по фону закрывает; Esc — тоже.
class TelegramMediaOverlayShell extends StatefulWidget {
  final Widget child;
  final Widget? topBar;
  final Widget? bottomBar;
  final bool showCloseButton;
  final MediaViewerContext? viewerContext;

  const TelegramMediaOverlayShell({
    super.key,
    required this.child,
    this.topBar,
    this.bottomBar,
    this.showCloseButton = false,
    this.viewerContext,
  });

  @override
  State<TelegramMediaOverlayShell> createState() =>
      _TelegramMediaOverlayShellState();
}

class _TelegramMediaOverlayShellState extends State<TelegramMediaOverlayShell> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.viewerContext;
    final chat = meta?.chatTitle.trim() ?? '';
    final date = meta?.dateLabel.trim() ?? '';
    final hasMeta = chat.isNotEmpty || date.isNotEmpty;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 88),
              child: Column(
                children: [
                  if (widget.topBar != null || widget.showCloseButton)
                    _TopChrome(
                      topBar: widget.topBar,
                      showClose: widget.showCloseButton,
                      onClose: _close,
                    ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        widget.child,
                      ],
                    ),
                  ),
                  if (widget.bottomBar != null) widget.bottomBar!,
                ],
              ),
            ),
          ),
          if (hasMeta)
            Positioned(
              left: 28,
              bottom: 88,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chat.isNotEmpty)
                      Text(
                        chat,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (date.isNotEmpty) ...[
                      if (chat.isNotEmpty) const SizedBox(height: 2),
                      Text(
                        date,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  final Widget? topBar;
  final bool showClose;
  final VoidCallback onClose;

  const _TopChrome({
    required this.topBar,
    required this.showClose,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: topBar ?? const SizedBox.shrink()),
          if (showClose)
            IconButton(
              tooltip: 'Закрыть',
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class TelegramMediaCard extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final double? maxHeight;

  const TelegramMediaCard({
    super.key,
    required this.child,
    this.maxWidth,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Material(
      color: const Color(0xF01E1E1E),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? size.width - 48,
          maxHeight: maxHeight ?? size.height - 120,
        ),
        child: child,
      ),
    );
  }
}
