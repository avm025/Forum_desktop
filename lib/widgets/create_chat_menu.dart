import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'folder_chat_picker.dart';

/// Пункты меню «+» в шапке списка чатов.
enum CreateChatMenuAction {
  message,
  group,
  aiChat,
  folder,
}

/// Модальное меню создания (как в iOS / Figma): карточка у кнопки карандаша.
class CreateChatMenu {
  CreateChatMenu._();

  static const _menuWidth = 300.0;
  static const _radius = 14.0;
  static const _edgePadding = 8.0;

  static double _menuWidthFor(double overlayWidth) {
    return math.min(_menuWidth, overlayWidth - _edgePadding * 2);
  }

  static double _clampRight(
    double right,
    double overlayWidth,
    double menuWidth,
  ) {
    final minRight = _edgePadding;
    final maxRight = math.max(minRight, overlayWidth - menuWidth - _edgePadding);
    return math.min(math.max(right, minRight), maxRight);
  }

  static Rect? _readAnchorRect(GlobalKey anchorKey) {
    try {
      final anchorContext = anchorKey.currentContext;
      if (anchorContext == null || !anchorContext.mounted) return null;
      final renderObject = anchorContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return null;
      final origin = renderObject.localToGlobal(Offset.zero);
      return origin & renderObject.size;
    } catch (_) {
      return null;
    }
  }

  static Future<CreateChatMenuAction?> show(
    BuildContext context, {
    required GlobalKey anchorKey,
  }) {
    final anchorRect = _readAnchorRect(anchorKey);
    return showGeneralDialog<CreateChatMenuAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: _MenuOverlay(
            anchorKey: anchorKey,
            initialAnchorRect: anchorRect,
            onSelected: (a) => Navigator.of(ctx).pop(a),
            onCancel: () => Navigator.of(ctx).pop(),
          ),
        );
      },
    );
  }

  /// Открыть меню и выполнить действие.
  static Future<void> open(BuildContext context, GlobalKey anchorKey) async {
    final action = await show(context, anchorKey: anchorKey);
    if (!context.mounted || action == null) return;

    switch (action) {
      case CreateChatMenuAction.folder:
        await FolderChatPicker.openCreate(context);
      case CreateChatMenuAction.message:
      case CreateChatMenuAction.group:
      case CreateChatMenuAction.aiChat:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скоро')),
        );
    }
  }
}

class _MenuOverlay extends StatefulWidget {
  final GlobalKey anchorKey;
  final Rect? initialAnchorRect;
  final ValueChanged<CreateChatMenuAction> onSelected;
  final VoidCallback onCancel;

  const _MenuOverlay({
    required this.anchorKey,
    required this.onSelected,
    required this.onCancel,
    this.initialAnchorRect,
  });

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay> {
  Rect? _anchorRect;

  @override
  void initState() {
    super.initState();
    _anchorRect = widget.initialAnchorRect;
  }

  Rect? _resolveAnchorRect() {
    final live = CreateChatMenu._readAnchorRect(widget.anchorKey);
    if (live != null) {
      _anchorRect = live;
    }
    return _anchorRect;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
        final menuWidth = CreateChatMenu._menuWidthFor(overlaySize.width);

        var top = 56.0;
        var right = CreateChatMenu._edgePadding;

        final anchorRect = _resolveAnchorRect();
        if (anchorRect != null) {
          top = anchorRect.bottom + 8;
          right = CreateChatMenu._clampRight(
            overlaySize.width - anchorRect.right,
            overlaySize.width,
            menuWidth,
          );
        }

        final maxMenuHeight = math.max(
          120.0,
          overlaySize.height - top - CreateChatMenu._edgePadding,
        );
        top = math.min(
          top,
          math.max(
            CreateChatMenu._edgePadding,
            overlaySize.height - maxMenuHeight - CreateChatMenu._edgePadding,
          ),
        );

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onCancel,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(color: Colors.black.withValues(alpha: 0.15)),
                  ),
                ),
              ),
              Positioned(
                top: top,
                right: right,
                width: menuWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxMenuHeight),
                  child: SingleChildScrollView(
                    child: _MenuCard(
                      palette: p,
                      compact: menuWidth < CreateChatMenu._menuWidth,
                      onSelected: widget.onSelected,
                      onCancel: widget.onCancel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuCard extends StatelessWidget {
  final ForumPalette palette;
  final bool compact;
  final ValueChanged<CreateChatMenuAction> onSelected;
  final VoidCallback onCancel;

  const _MenuCard({
    required this.palette,
    required this.onSelected,
    required this.onCancel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bg2,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(CreateChatMenu._radius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuRow(
            label: 'Написать сообщение',
            icon: Icons.add_comment_outlined,
            palette: palette,
            compact: compact,
            onTap: () => onSelected(CreateChatMenuAction.message),
          ),
          _divider(palette),
          _MenuRow(
            label: 'Создать группу',
            icon: Icons.people_outline_rounded,
            palette: palette,
            compact: compact,
            onTap: () => onSelected(CreateChatMenuAction.group),
          ),
          _divider(palette),
          _MenuRow(
            label: 'Создать чат с ИИ',
            icon: Icons.diamond_outlined,
            palette: palette,
            compact: compact,
            onTap: () => onSelected(CreateChatMenuAction.aiChat),
          ),
          _divider(palette),
          _MenuRow(
            label: 'Создать папку',
            icon: Icons.folder_outlined,
            palette: palette,
            compact: compact,
            onTap: () => onSelected(CreateChatMenuAction.folder),
          ),
          const SizedBox(height: 6),
          _divider(palette),
          _MenuRow(
            label: 'Отмена',
            icon: Icons.close_rounded,
            palette: palette,
            compact: compact,
            labelColor: const Color(0xFFFF453A),
            iconColor: const Color(0xFFFF453A),
            onTap: onCancel,
          ),
        ],
      ),
    );
  }

  Widget _divider(ForumPalette p) =>
      Divider(height: 1, thickness: 1, color: p.border1);
}

class _MenuRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final ForumPalette palette;
  final VoidCallback onTap;
  final bool compact;
  final Color? labelColor;
  final Color? iconColor;

  const _MenuRow({
    required this.label,
    required this.icon,
    required this.palette,
    required this.onTap,
    this.compact = false,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: compact ? 12 : 14,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: labelColor ?? palette.text1,
                  fontSize: compact ? 15 : 16,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: compact ? 20 : 22,
              color: iconColor ?? palette.text2,
            ),
          ],
        ),
      ),
    );
  }
}
