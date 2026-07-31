import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../models/msg_read_entry.dart';
import '../models/telegram_reactions.dart';
import '../theme/app_theme.dart';
import '../utils/msg_read_display.dart';
import 'avatar_widget.dart';

double _clampRange(double value, double min, double max) {
  if (max < min) return min;
  return value.clamp(min, max);
}

/// Конфиг пункта «просмотры» в контекстном меню (`msg_read_list`).
class MsgReadViewsConfig {
  final bool isGroup;
  final Future<List<MsgReadEntry>> Function() load;
  final List<String>? Function(MsgReadEntry entry)? avatarColors;

  const MsgReadViewsConfig({
    required this.isGroup,
    required this.load,
    this.avatarColors,
  });
}

/// Пункт контекстного меню сообщения (как в Telegram Desktop).
class MessageContextAction {
  final String id;
  final String label;
  final IconData icon;
  final Color? color;
  final bool destructive;

  const MessageContextAction({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
    this.destructive = false,
  });
}

/// Контроллер открытого меню сообщения (overlay).
class MessageContextMenuController {
  MessageContextMenuController._();
  static final MessageContextMenuController instance =
      MessageContextMenuController._();

  OverlayEntry? _entry;
  _MessageContextMenuOverlayState? _state;
  GlobalKey? _openForKey;
  Completer<String?>? _completer;

  void _rebuildOverlay() => _entry?.markNeedsBuild();

  bool isOpenFor(GlobalKey key) => identical(_openForKey, key);

  void handleBubbleTap(GlobalKey key) {
    if (!isOpenFor(key) || _state == null) return;
    if (_state!.isExpanded) {
      _state!.collapse();
    } else {
      close();
    }
  }

  void closeIfOpenFor(GlobalKey key) {
    if (isOpenFor(key)) close();
  }

  void close([String? result]) {
    _entry?.remove();
    _entry = null;
    _state = null;
    _openForKey = null;
    final c = _completer;
    _completer = null;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  Future<String?> show({
    required BuildContext context,
    required GlobalKey anchorKey,
    required List<MessageContextAction> actions,
    List<String> reactions = const [],
    void Function(String emoji)? onReaction,
    Offset? globalPosition,
    MsgReadViewsConfig? readViews,
  }) async {
    close();

    if (actions.isEmpty && reactions.isEmpty && readViews == null) return null;

    final position = globalPosition ?? _bubbleGlobalPosition(anchorKey);
    if (position == Offset.zero && globalPosition == null) return null;

    _openForKey = anchorKey;
    _completer = Completer<String?>();

    _entry = OverlayEntry(
      builder: (overlayContext) => _MessageContextMenuOverlay(
        anchorKey: anchorKey,
        anchorPosition: position,
        actions: actions,
        reactions: reactions,
        onReaction: onReaction,
        onAction: (id) => close(id),
        onDismiss: () => close(),
        onStateReady: (state) => _state = state,
        onRebuild: _rebuildOverlay,
        readViews: readViews,
      ),
    );

    Overlay.of(context).insert(_entry!);
    return _completer!.future;
  }
}

class _MessageContextMenuOverlay extends StatefulWidget {
  final GlobalKey anchorKey;
  final Offset anchorPosition;
  final List<MessageContextAction> actions;
  final List<String> reactions;
  final void Function(String emoji)? onReaction;
  final void Function(String actionId) onAction;
  final VoidCallback onDismiss;
  final void Function(_MessageContextMenuOverlayState state) onStateReady;
  final VoidCallback onRebuild;
  final MsgReadViewsConfig? readViews;

  const _MessageContextMenuOverlay({
    required this.anchorKey,
    required this.anchorPosition,
    required this.actions,
    required this.reactions,
    required this.onReaction,
    required this.onAction,
    required this.onDismiss,
    required this.onStateReady,
    required this.onRebuild,
    this.readViews,
  });

  @override
  State<_MessageContextMenuOverlay> createState() =>
      _MessageContextMenuOverlayState();
}

class _MessageContextMenuOverlayState extends State<_MessageContextMenuOverlay> {
  static const actionsWidth = 240.0;
  static const panelWidth = actionsWidth + 28;
  static const actionHeight = 40.0;
  static const emojiCell = 34.0;
  static const emojiPerRow = 7;
  static const emojiRowGap = 4.0;
  static const emojiPadV = 8.0;
  static const emojiPadH = 6.0;
  static const blockGap = 6.0;
  static const collapsedVisible = kTelegramCollapsedReactionCount;

  double get _innerPanelWidth => panelWidth - emojiPadH * 2;

  double _cellSize(int slots) {
    if (slots <= 0) return emojiCell;
    return (_innerPanelWidth / slots).clamp(30.0, emojiCell);
  }

  double _collapsedCellSize(int visibleCount, bool canExpand) {
    final slots = visibleCount + (canExpand ? 1 : 0);
    return _cellSize(slots);
  }

  double _expandedCellSize() => _cellSize(emojiPerRow);

  bool _expanded = false;

  bool get isExpanded => _expanded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onStateReady(this);
    });
  }

  void collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    widget.onRebuild();
  }

  void expand() {
    if (_expanded) return;
    setState(() => _expanded = true);
    widget.onRebuild();
  }

  double _reactionHeight(int reactionRows, double cellHeight) {
    if (widget.reactions.isEmpty || reactionRows == 0) return 0;
    return emojiPadV * 2 +
        reactionRows * cellHeight +
        (reactionRows - 1) * emojiRowGap;
  }

  double _maxExpandedReactionHeight(Size screen, double belowHeight) {
    return _clampRange(
      screen.height - belowHeight - 16,
      100.0,
      screen.height * 0.52,
    );
  }

  ({double left, double top, double expandedMaxHeight}) _layout(Size screen) {
    final visibleCount = widget.reactions.length.clamp(0, collapsedVisible);
    final canExpand = widget.reactions.length > collapsedVisible;
    final collapsedCell = _collapsedCellSize(visibleCount, canExpand);
    final expandedCell = _expandedCellSize();

    final reactionRows = widget.reactions.isEmpty
        ? 0
        : _expanded
            ? (widget.reactions.length / emojiPerRow).ceil()
            : 1;
    final actionsHeight = (widget.actions.isEmpty && widget.readViews == null)
        ? 0.0
        : (widget.actions.length + (widget.readViews != null ? 1 : 0)) *
                actionHeight +
            (widget.actions.any((a) => a.destructive) ? 8 : 0) +
            8;
    final gap = widget.reactions.isNotEmpty &&
            (widget.actions.isNotEmpty || widget.readViews != null)
        ? blockGap
        : 0.0;

    final expandedMaxHeight = _expanded && widget.reactions.isNotEmpty
        ? _maxExpandedReactionHeight(screen, actionsHeight + gap)
        : 0.0;

    final rawReactionHeight = _reactionHeight(
      reactionRows,
      _expanded ? expandedCell : collapsedCell,
    );
    final reactionHeight = _expanded && expandedMaxHeight > 0
        ? rawReactionHeight.clamp(0.0, expandedMaxHeight)
        : rawReactionHeight;

    final totalHeight = reactionHeight + gap + actionsHeight;

    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlayBox.globalToLocal(widget.anchorPosition);

    var left = local.dx - panelWidth / 2;
    var top = local.dy - totalHeight / 2;

    if (left + panelWidth > screen.width - 8) {
      left = screen.width - panelWidth - 8;
    }
    if (top + totalHeight > screen.height - 8) {
      top = screen.height - totalHeight - 8;
    }
    left = _clampRange(left, 8.0, max(8.0, screen.width - panelWidth - 8));
    top = _clampRange(top, 8.0, max(8.0, screen.height - totalHeight - 8));

    return (
      left: left,
      top: top,
      expandedMaxHeight: expandedMaxHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screen = MediaQuery.sizeOf(context);
    final pos = _layout(screen);

    final visibleReactions = _expanded
        ? widget.reactions
        : widget.reactions.take(collapsedVisible).toList();
    final canExpand = widget.reactions.length > collapsedVisible;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: pos.left,
          top: pos.top,
          width: panelWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.reactions.isNotEmpty)
                SizedBox(
                  width: panelWidth,
                  child: Material(
                    color: p.bg2.withValues(alpha: 0.98),
                    elevation: 12,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        _expanded ? 14 : 22,
                      ),
                      side: BorderSide(
                        color: p.border1.withValues(alpha: 0.5),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          emojiPadH,
                          emojiPadV,
                          emojiPadH,
                          emojiPadV,
                        ),
                        child: _expanded
                            ? ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: pos.expandedMaxHeight,
                                ),
                                child: SingleChildScrollView(
                                  primary: false,
                                  child: _ReactionGrid(
                                    reactions: widget.reactions,
                                    perRow: emojiPerRow,
                                    rowGap: emojiRowGap,
                                    onPick: _pickReaction,
                                  ),
                                ),
                              )
                            : _ReactionRow(
                                reactions: visibleReactions,
                                showExpand: canExpand,
                                expanded: false,
                                onPick: _pickReaction,
                                onExpand: expand,
                              ),
                      ),
                    ),
                  ),
                ),
              if (widget.reactions.isNotEmpty &&
                  (widget.actions.isNotEmpty || widget.readViews != null))
                const SizedBox(height: blockGap),
              if (widget.actions.isNotEmpty || widget.readViews != null)
                Material(
                  color: p.bg2,
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: p.border1.withValues(alpha: 0.65)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: actionsWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.readViews != null)
                          _MsgReadViewsTile(
                            config: widget.readViews!,
                            palette: p,
                            onOpenList: () => widget.onAction('views'),
                          ),
                        for (var i = 0; i < widget.actions.length; i++)
                          _ActionTile(
                            action: widget.actions[i],
                            palette: p,
                            showDividerBefore:
                                widget.actions[i].destructive && i > 0,
                            onTap: () => widget.onAction(widget.actions[i].id),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _pickReaction(String emoji) {
    widget.onReaction?.call(emoji);
    widget.onDismiss();
  }
}

class _ReactionRow extends StatelessWidget {
  final List<String> reactions;
  final bool showExpand;
  final bool expanded;
  final void Function(String emoji) onPick;
  final VoidCallback onExpand;

  const _ReactionRow({
    required this.reactions,
    required this.showExpand,
    required this.expanded,
    required this.onPick,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final slots = reactions.length + (showExpand ? 1 : 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = slots > 0
            ? (constraints.maxWidth / slots).clamp(30.0, 34.0)
            : 34.0;
        final fontSize = (cell * 0.76).clamp(22.0, 28.0);
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            for (final emoji in reactions)
              _ReactionCell(
                emoji: emoji,
                size: cell,
                fontSize: fontSize,
                onTap: () => onPick(emoji),
              ),
            if (showExpand)
              _ExpandButton(
                size: cell,
                expanded: expanded,
                palette: p,
                onTap: onExpand,
              ),
          ],
        );
      },
    );
  }
}

class _ReactionGrid extends StatelessWidget {
  final List<String> reactions;
  final int perRow;
  final double rowGap;
  final void Function(String emoji) onPick;

  const _ReactionGrid({
    required this.reactions,
    required this.perRow,
    required this.rowGap,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth / perRow).clamp(30.0, 34.0);
        final fontSize = (cell * 0.76).clamp(22.0, 28.0);
        final rows = <Widget>[];
        for (var i = 0; i < reactions.length; i += perRow) {
          final slice = reactions.sublist(
            i,
            (i + perRow).clamp(0, reactions.length),
          );
          rows.add(
            Row(
              children: [
                for (final emoji in slice)
                  _ReactionCell(
                    emoji: emoji,
                    size: cell,
                    fontSize: fontSize,
                    onTap: () => onPick(emoji),
                  ),
                for (var j = slice.length; j < perRow; j++)
                  SizedBox(width: cell, height: cell),
              ],
            ),
          );
          if (i + perRow < reactions.length) {
            rows.add(SizedBox(height: rowGap));
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class _ExpandButton extends StatelessWidget {
  final double size;
  final bool expanded;
  final ForumPalette palette;
  final VoidCallback onTap;

  const _ExpandButton({
    required this.size,
    required this.expanded,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Container(
              width: size - 6,
              height: size - 6,
              decoration: BoxDecoration(
                color: palette.bg3.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              child: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: palette.text2,
                size: (size * 0.52).clamp(16.0, 20.0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionCell extends StatefulWidget {
  final String emoji;
  final double size;
  final double fontSize;
  final VoidCallback onTap;

  const _ReactionCell({
    required this.emoji,
    required this.size,
    required this.fontSize,
    required this.onTap,
  });

  @override
  State<_ReactionCell> createState() => _ReactionCellState();
}

class _ReactionCellState extends State<_ReactionCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hover ? 1.22 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: Text(
                widget.emoji,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final MessageContextAction action;
  final ForumPalette palette;
  final bool showDividerBefore;
  final VoidCallback onTap;

  const _ActionTile({
    required this.action,
    required this.palette,
    required this.showDividerBefore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = action.color ??
        (action.destructive ? Colors.redAccent : palette.text1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDividerBefore)
          Divider(height: 8, color: palette.border1.withValues(alpha: 0.55)),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(action.icon, size: 20, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    action.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Offset _bubbleGlobalPosition(GlobalKey anchorKey) {
  final anchorContext = anchorKey.currentContext;
  if (anchorContext == null) return Offset.zero;
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Offset.zero;
  final origin = box.localToGlobal(Offset.zero);
  return Offset(
    origin.dx + box.size.width / 2,
    origin.dy + box.size.height / 2,
  );
}

class _MsgReadViewsTile extends StatefulWidget {
  final MsgReadViewsConfig config;
  final ForumPalette palette;
  final VoidCallback onOpenList;

  const _MsgReadViewsTile({
    required this.config,
    required this.palette,
    required this.onOpenList,
  });

  @override
  State<_MsgReadViewsTile> createState() => _MsgReadViewsTileState();
}

class _MsgReadViewsTileState extends State<_MsgReadViewsTile>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<MsgReadEntry> _entries = const [];
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.config.load();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
      _pulse.stop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _loading = false;
      });
      _pulse.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final canOpen = widget.config.isGroup && !_loading;
    final label = _loading
        ? null
        : (widget.config.isGroup
            ? MsgReadDisplay.viewsLabel(_entries.length)
            : MsgReadDisplay.privateMenuLabel(_entries));

    return InkWell(
      onTap: canOpen ? widget.onOpenList : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.done_all_rounded, size: 20, color: p.lime),
            const SizedBox(width: 14),
            Expanded(
              child: _loading
                  ? FadeTransition(
                      opacity: Tween(begin: 0.35, end: 0.85).animate(_pulse),
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: p.text3.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    )
                  : Text(
                      label ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            ),
            if (widget.config.isGroup) ...[
              const SizedBox(width: 8),
              if (_loading)
                FadeTransition(
                  opacity: Tween(begin: 0.35, end: 0.85).animate(_pulse),
                  child: SizedBox(
                    width: 54,
                    height: 22,
                    child: Stack(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Positioned(
                            left: i * 14.0,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: p.text3.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              else if (_entries.isNotEmpty)
                SizedBox(
                  width: 14.0 * (_entries.take(3).length - 1).clamp(0, 2) + 22,
                  height: 22,
                  child: Stack(
                    children: [
                      for (var i = 0; i < _entries.take(3).length; i++)
                        Positioned(
                          left: i * 14.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.bg2, width: 1.5),
                            ),
                            child: AvatarWidget(
                              name: _entries[i].name.isNotEmpty
                                  ? _entries[i].name
                                  : '?',
                              avatarUrl: _entries[i].avatarUrl,
                              avatarColor:
                                  widget.config.avatarColors?.call(_entries[i]),
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (canOpen) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.text3),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showMessageActions({
  required BuildContext context,
  required GlobalKey anchorKey,
  required VoidCallback onReply,
  VoidCallback? onCall,
  VoidCallback? onForward,
  VoidCallback? onCopy,
  VoidCallback? onOpen,
  VoidCallback? onDelete,
  MsgReadViewsConfig? readViews,
  void Function(List<MsgReadEntry> entries)? onViews,
  List<String> reactions = const [],
  void Function(String emoji)? onReaction,
  Offset? globalPosition,
}) async {
  List<MsgReadEntry> loadedViews = const [];

  final actions = <MessageContextAction>[
    if (onCall != null)
      const MessageContextAction(
        id: 'call',
        label: 'Позвонить',
        icon: Icons.phone_rounded,
      ),
    const MessageContextAction(
      id: 'reply',
      label: 'Ответить',
      icon: Icons.reply_rounded,
    ),
    if (onForward != null)
      const MessageContextAction(
        id: 'forward',
        label: 'Переслать',
        icon: Icons.forward_rounded,
      ),
    if (onCopy != null)
      const MessageContextAction(
        id: 'copy',
        label: 'Копировать',
        icon: Icons.copy_rounded,
      ),
    if (onOpen != null)
      const MessageContextAction(
        id: 'open',
        label: 'Открыть',
        icon: Icons.open_in_new_rounded,
      ),
    if (onDelete != null)
      const MessageContextAction(
        id: 'delete',
        label: 'Удалить',
        icon: Icons.delete_outline_rounded,
        destructive: true,
      ),
  ];

  final selected = await MessageContextMenuController.instance.show(
    context: context,
    anchorKey: anchorKey,
    actions: actions,
    reactions: onReaction != null ? reactions : const [],
    onReaction: onReaction,
    globalPosition: globalPosition,
    readViews: readViews == null
        ? null
        : MsgReadViewsConfig(
            isGroup: readViews.isGroup,
            avatarColors: readViews.avatarColors,
            load: () async {
              loadedViews = await readViews.load();
              return loadedViews;
            },
          ),
  );

  switch (selected) {
    case 'views':
      onViews?.call(loadedViews);
    case 'call':
      onCall?.call();
    case 'reply':
      onReply();
    case 'forward':
      onForward?.call();
    case 'copy':
      onCopy?.call();
    case 'open':
      onOpen?.call();
    case 'delete':
      onDelete?.call();
  }
}
