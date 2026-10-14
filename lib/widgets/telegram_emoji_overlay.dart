import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'telegram_emoji_panel.dart';

/// Позиция панели относительно якоря.
enum TelegramEmojiPlacement {
  /// Над иконкой смайла (чат).
  aboveIcon,
  /// Справа от карточки (окно пересылки файлов).
  besideCard,
}

/// Общий overlay панели смайлов (чат и пересылка файлов).
class TelegramEmojiOverlay {
  TelegramEmojiOverlay._();

  static const width = 332.0;
  static const height = 420.0;
  static const animDuration = Duration(milliseconds: 160);
  static const hideDelay = Duration(milliseconds: 160);
}

const Object kTelegramEmojiTapGroup = Object();

class _EmojiOverlayAnimController {
  VoidCallback? _dismissAnimated;

  Future<void> dismiss() async {
    final fn = _dismissAnimated;
    if (fn == null) return;
    fn();
    await Future<void>.delayed(TelegramEmojiOverlay.animDuration);
  }

  void bind(VoidCallback dismissAnimated) {
    _dismissAnimated = dismissAnimated;
  }

  void unbind() {
    _dismissAnimated = null;
  }
}

class _EmojiModalGeom {
  final double left;
  final double top;
  final double width;
  final double height;

  const _EmojiModalGeom({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

mixin TelegramEmojiOverlayHost<T extends StatefulWidget> on State<T> {
  OverlayEntry? emojiOverlay;
  bool emojiOpen = false;
  Timer? emojiHideTimer;
  final GlobalKey emojiIconKey = GlobalKey();
  final GlobalKey emojiBesideKey = GlobalKey();
  TelegramEmojiPlacement emojiPlacement = TelegramEmojiPlacement.aboveIcon;
  final _EmojiOverlayAnimController _anim = _EmojiOverlayAnimController();
  ValueChanged<String>? _onEmoji;

  /// Геометрия модалки в координатах Overlay: у якоря, без обрезки окном.
  _EmojiModalGeom _modalGeom(TelegramEmojiPlacement placement) {
    const w = TelegramEmojiOverlay.width;
    const preferH = TelegramEmojiOverlay.height;
    const gap = 8.0;
    const pad = 8.0;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final key = placement == TelegramEmojiPlacement.besideCard
        ? emojiBesideKey
        : emojiIconKey;
    final box = key.currentContext?.findRenderObject() as RenderBox?;

    if (overlayBox == null ||
        !overlayBox.hasSize ||
        box == null ||
        !box.hasSize) {
      return const _EmojiModalGeom(
        left: 80,
        top: 80,
        width: w,
        height: preferH,
      );
    }

    final area = overlayBox.size;
    // Координаты якоря относительно Overlay — не окна/экрана.
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchor = box.size;

    double left;
    double top;
    double h = preferH;

    if (placement == TelegramEmojiPlacement.besideCard) {
      left = origin.dx + anchor.width + gap;
      top = origin.dy;
      // Если справа не влезает — слева от карточки.
      if (left + w > area.width - pad) {
        left = origin.dx - w - gap;
      }
      // Высота по доступному месту вниз от верха карточки.
      final availDown = area.height - top - pad;
      h = math.min(preferH, math.max(280.0, availDown));
    } else {
      // Над иконкой: низ панели чуть выше иконки, растём вверх.
      left = origin.dx;
      final availUp = origin.dy - pad - gap;
      h = math.min(preferH, math.max(280.0, availUp));
      top = origin.dy - h - gap;
    }

    // Только сдвиг, чтобы целиком попасть в Overlay (не left/right/top/bottom: 0).
    final maxLeft = math.max(pad, area.width - w - pad);
    final maxTop = math.max(pad, area.height - h - pad);
    left = left.clamp(pad, maxLeft);
    top = top.clamp(pad, maxTop);

    return _EmojiModalGeom(left: left, top: top, width: w, height: h);
  }

  void insertEmojiOverlay({
    required ValueChanged<String> onEmoji,
    TelegramEmojiPlacement placement = TelegramEmojiPlacement.aboveIcon,
  }) {
    emojiHideTimer?.cancel();
    if (emojiOpen || emojiOverlay != null) return;
    _onEmoji = onEmoji;
    emojiPlacement = placement;
    final p = context.palette;
    final geom = _modalGeom(placement);
    emojiOpen = true;
    emojiOverlay = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: geom.left,
          top: geom.top,
          width: geom.width,
          height: geom.height,
          child: _AnimatedEmojiOverlay(
            palette: p,
            width: geom.width,
            height: geom.height,
            anim: _anim,
            onEmoji: (e) => _onEmoji?.call(e),
            onDismiss: hideEmojiOverlay,
            onEnter: cancelHideEmojiOverlay,
            onExit: scheduleHideEmojiOverlay,
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(emojiOverlay!);
    if (mounted) setState(() {});
  }

  void removeEmojiOverlayEntry() {
    _anim.unbind();
    emojiOverlay?.remove();
    emojiOverlay = null;
  }

  Future<void> hideEmojiOverlay() async {
    emojiHideTimer?.cancel();
    if (!emojiOpen && emojiOverlay == null) return;
    emojiOpen = false;
    if (mounted) setState(() {});
    await _anim.dismiss();
    removeEmojiOverlayEntry();
    if (mounted) setState(() {});
  }

  void scheduleHideEmojiOverlay() {
    emojiHideTimer?.cancel();
    emojiHideTimer = Timer(TelegramEmojiOverlay.hideDelay, () {
      if (!mounted) return;
      unawaited(hideEmojiOverlay());
    });
  }

  void cancelHideEmojiOverlay() {
    emojiHideTimer?.cancel();
  }

  void openEmojiOverlayOnHover({
    required ValueChanged<String> onEmoji,
    TelegramEmojiPlacement placement = TelegramEmojiPlacement.aboveIcon,
  }) {
    cancelHideEmojiOverlay();
    if (!emojiOpen) {
      insertEmojiOverlay(onEmoji: onEmoji, placement: placement);
    }
  }

  void toggleEmojiOverlay({
    required ValueChanged<String> onEmoji,
    TelegramEmojiPlacement placement = TelegramEmojiPlacement.aboveIcon,
  }) {
    if (emojiOpen) {
      unawaited(hideEmojiOverlay());
    } else {
      insertEmojiOverlay(onEmoji: onEmoji, placement: placement);
    }
  }

  /// Иконка смайла: hover открывает плавно, клик — toggle.
  Widget buildEmojiIconButton({
    required ForumPalette palette,
    required ValueChanged<String> onEmoji,
    required double iconSize,
    TelegramEmojiPlacement placement = TelegramEmojiPlacement.aboveIcon,
    bool enabled = true,
  }) {
    return TapRegion(
      groupId: kTelegramEmojiTapGroup,
      child: MouseRegion(
        key: emojiIconKey,
        onEnter: !enabled
            ? null
            : (_) => openEmojiOverlayOnHover(
                  onEmoji: onEmoji,
                  placement: placement,
                ),
        onExit: !enabled ? null : (_) => scheduleHideEmojiOverlay(),
        child: IconButton(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: !enabled
              ? null
              : () => toggleEmojiOverlay(
                    onEmoji: onEmoji,
                    placement: placement,
                  ),
          icon: Icon(
            Icons.emoji_emotions_outlined,
            color: emojiOpen ? palette.purple : palette.text2,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  void disposeEmojiOverlay() {
    emojiHideTimer?.cancel();
    removeEmojiOverlayEntry();
  }
}

class _AnimatedEmojiOverlay extends StatefulWidget {
  final ForumPalette palette;
  final double width;
  final double height;
  final _EmojiOverlayAnimController anim;
  final ValueChanged<String> onEmoji;
  final VoidCallback onDismiss;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  const _AnimatedEmojiOverlay({
    required this.palette,
    required this.width,
    required this.height,
    required this.anim,
    required this.onEmoji,
    required this.onDismiss,
    required this.onEnter,
    required this.onExit,
  });

  @override
  State<_AnimatedEmojiOverlay> createState() => _AnimatedEmojiOverlayState();
}

class _AnimatedEmojiOverlayState extends State<_AnimatedEmojiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: TelegramEmojiOverlay.animDuration,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    widget.anim.bind(() {
      if (mounted) unawaited(_controller.reverse());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.forward());
    });
  }

  @override
  void dispose() {
    widget.anim.unbind();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.bottomLeft,
        child: TapRegion(
          groupId: kTelegramEmojiTapGroup,
          onTapOutside: (_) => widget.onDismiss(),
          child: MouseRegion(
            onEnter: (_) => widget.onEnter(),
            onExit: (_) => widget.onExit(),
            child: Material(
              elevation: 12,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              color: widget.palette.bg1,
              clipBehavior: Clip.antiAlias,
              child: TelegramEmojiPanel(
                width: widget.width,
                height: widget.height,
                showClose: false,
                onEmoji: widget.onEmoji,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
