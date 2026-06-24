import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../terminal/session_status.dart';
import 'shell_responsive.dart';
import 'shell_state.dart';
import 'tab_context_menu.dart';
import 'tab_pill.dart';

/// The tab strip for ONE group (ADR 0018). Stateful: owns the horizontal scroll
/// controller, the drag-over insertion index, per-pill keys (geometry +
/// ensure-visible) and the overflow ("more") menu. All mutations are reported
/// through callbacks the shell wires to [TabsController].
class ShellTabBar extends StatefulWidget {
  final TabGroup group;
  final Map<String, ShellTab> tabs;
  final bool isActiveGroup;
  final bool canReopen;

  /// Whether tabs can be detached into a separate OS window (desktop only).
  final bool canDetach;

  /// Live status listenable for a terminal tab (null for management tabs).
  final ValueListenable<SessionStatus>? Function(String tabId) statusFor;

  /// Whether [tabId] has a manual-reconnect affordance (ADR 0032 D5).
  final bool Function(String tabId) canReconnectFor;

  final void Function(String tabId) onSelect;
  final void Function(TabAction action, String tabId) onAction;

  /// Commit a manual tab title from the pill's inline rename (ADR 0036 D2).
  final void Function(String tabId, String newTitle) onRenameTab;

  /// Open the new-session launcher (home/welcome) — the SAME path as
  /// double-tapping empty strip space (ADR 0036 D1). Does NOT persist anything.
  final VoidCallback onNewTab;

  /// Split the active group to the right from the strip (ADR 0036 D6). Mirrors
  /// the ⌘\ shortcut + the "Sağa Böl" context-menu item.
  final VoidCallback onSplitRight;

  /// Whether a split-right is currently possible (the active group has >=2 tabs).
  /// Drives the enabled/disabled state of the strip's split button.
  final bool canSplit;

  /// Whether a split currently exists (>=2 groups) so "Birleştir" (merge) is
  /// reachable from the context menu (ADR 0036 D6).
  final bool canMerge;

  final void Function(TabDragData data, String targetGroupId, int insertIndex)
  onDrop;
  final void Function(String tabId) onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDoubleTapEmpty;

  const ShellTabBar({
    super.key,
    required this.group,
    required this.tabs,
    required this.isActiveGroup,
    required this.canReopen,
    required this.statusFor,
    required this.canReconnectFor,
    required this.onSelect,
    required this.onAction,
    required this.onRenameTab,
    required this.onNewTab,
    required this.onSplitRight,
    required this.canSplit,
    required this.canMerge,
    required this.onDrop,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDoubleTapEmpty,
    this.canDetach = false,
  });

  @override
  State<ShellTabBar> createState() => _ShellTabBarState();
}

class _ShellTabBarState extends State<ShellTabBar> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _pillKeys = {};
  int? _dropIndex;

  /// Whether the strip actually overflows its width. Gates the overflow caret
  /// AND the edge-fade (ADR 0036 D7) so neither shows when everything fits.
  /// Recomputed post-layout from the scroll position's max extent.
  bool _overflowing = false;

  /// Current horizontal scroll offset, mirrored so the edge-fade can drop the
  /// leading fade at the start and the trailing fade at the end.
  double _scrollOffset = 0;

  /// Pill density for the current panel width, recomputed each layout from the
  /// strip's [LayoutBuilder] (ADR 0021). As the panel narrows, titles shrink and
  /// then pills drop to icon-only.
  TabPillMode _pillMode = const TabPillMode(false, 160);

  // Manual double-tap detection for empty strip space (see _onPointerDown).
  Duration? _lastEmptyDownAt;
  Offset? _lastEmptyDownPos;

  List<String> get _ids =>
      widget.group.tabIds.where((id) => widget.tabs[id] != null).toList();

  GlobalKey _keyFor(String id) => _pillKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final off = _scroll.offset;
    if (off != _scrollOffset) setState(() => _scrollOffset = off);
  }

  /// Recompute [_overflowing] from the live scroll extent after layout. Called
  /// post-frame so the scroll controller has measured its content (ADR 0036 D7).
  void _scheduleOverflowSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        if (_overflowing) setState(() => _overflowing = false);
        return;
      }
      final over = _scroll.position.maxScrollExtent > 0.5;
      if (over != _overflowing || _scroll.offset != _scrollOffset) {
        setState(() {
          _overflowing = over;
          _scrollOffset = _scroll.offset;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleEnsureVisible();
    _scheduleOverflowSync();
  }

  @override
  void didUpdateWidget(ShellTabBar old) {
    super.didUpdateWidget(old);
    if (old.group.activeTabId != widget.group.activeTabId) {
      _scheduleEnsureVisible();
    }
    // Prune keys for tabs that no longer exist in this group.
    final live = _ids.toSet();
    _pillKeys.removeWhere((id, _) => !live.contains(id));
    // Tab set / width may have changed: re-evaluate overflow next frame.
    _scheduleOverflowSync();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleEnsureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = widget.group.activeTabId;
      if (id == null) return;
      final ctx = _pillKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          alignment: 0.5,
        );
      }
    });
  }

  bool _isOverPill(Offset globalPos) {
    for (final id in _ids) {
      final box =
          _pillKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPos)) return true;
    }
    return false;
  }

  /// Passive double-tap detection on empty strip space. Runs off raw pointer
  /// events so it never competes in the gesture arena (which would delay the
  /// pills' single-tap selection).
  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryMouseButton && e.buttons != 0) return;
    if (_isOverPill(e.position)) {
      _lastEmptyDownAt = null;
      return;
    }
    final now = e.timeStamp;
    final near =
        _lastEmptyDownPos != null &&
        (e.position - _lastEmptyDownPos!).distance < kDoubleTapSlop;
    if (_lastEmptyDownAt != null &&
        now - _lastEmptyDownAt! < kDoubleTapTimeout &&
        near) {
      _lastEmptyDownAt = null;
      widget.onDoubleTapEmpty();
    } else {
      _lastEmptyDownAt = now;
      _lastEmptyDownPos = e.position;
    }
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
    final pos = _scroll.position;
    final target = (_scroll.offset + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _scroll.jumpTo(target);
  }

  /// Insertion slot (0..n) for a global pointer x, in RENDERED order (the
  /// dragged tab is still counted — [TabsController.moveTab] adjusts).
  int _indexForGlobalX(double gx) {
    final ids = _ids;
    for (var i = 0; i < ids.length; i++) {
      final ctx = _pillKeys[ids[i]]?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final centerX = box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
      if (gx < centerX) return i;
    }
    return ids.length;
  }

  Future<void> _openContextMenu(
    BuildContext context,
    ShellTab tab,
    Offset pos,
  ) async {
    final action = await showTabContextMenu(
      context,
      pos,
      tab: tab,
      canReopen: widget.canReopen,
      canSplit: widget.group.tabIds.length >= 2,
      canMerge: widget.canMerge,
      canDetach: widget.canDetach,
      canReconnect: widget.canReconnectFor(tab.id),
    );
    if (action != null) widget.onAction(action, tab.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(left: 8),
      // Measure the panel/strip width so pills can shrink → icon-only (ADR 0021).
      child: LayoutBuilder(
        builder: (context, cons) {
          _pillMode = tabPillMode(cons.maxWidth);
          // Trailing cluster: [ + ][ split ][ overflow-caret? ] (ADR 0036 D1/D6).
          // The new-tab + split buttons are always visible; the caret only when
          // the strip actually overflows (D7).
          return Row(
            children: [
              Expanded(
                // Double-clicking empty strip space opens the new-session
                // launcher. Detected with a PASSIVE Listener (not a
                // GestureDetector) so it never enters the gesture arena and
                // never delays a single tab tap with a double-tap wait. We
                // manually hit-test the pill rects so the double-tap only fires
                // on genuinely empty space.
                child: Listener(
                  onPointerSignal: _onWheel,
                  onPointerDown: _onPointerDown,
                  child: DragTarget<TabDragData>(
                    onMove: (d) {
                      final idx = _indexForGlobalX(d.offset.dx);
                      if (idx != _dropIndex) setState(() => _dropIndex = idx);
                    },
                    onLeave: (_) {
                      if (_dropIndex != null) setState(() => _dropIndex = null);
                    },
                    onAcceptWithDetails: (d) {
                      final idx = _indexForGlobalX(d.offset.dx);
                      widget.onDrop(d.data, widget.group.id, idx);
                      setState(() => _dropIndex = null);
                    },
                    builder: (ctx, cand, rej) => _edgeFade(
                      context,
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _scroll,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _pillRow(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _newTabButton(context),
              _splitButton(context),
              if (_overflowing) _moreButton(context),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _pillRow(BuildContext context) {
    final ids = _ids;
    final children = <Widget>[];
    for (var i = 0; i < ids.length; i++) {
      if (_dropIndex == i) children.add(_indicator(context));
      final id = ids[i];
      final tab = widget.tabs[id]!;
      // Same rule as the context menu: only terminals can be torn into their own
      // window (ADR 0020/0021). Drag-out reuses the detach action so it follows
      // the exact same path as right-click → "Ayrı Pencereye Taşı".
      final detachable = widget.canDetach && tab.kind == TabKind.terminal;
      children.add(
        TabPill(
          key: _keyFor(id),
          tab: tab,
          active: id == widget.group.activeTabId,
          isActiveGroup: widget.isActiveGroup,
          sourceGroupId: widget.group.id,
          sessionStatus: widget.statusFor(id),
          iconOnly: _pillMode.iconOnly,
          maxTitleWidth: _pillMode.maxTitleWidth,
          onSelect: () => widget.onSelect(id),
          onClose: () => widget.onAction(TabAction.close, id),
          onContextMenu: (pos) => _openContextMenu(context, tab, pos),
          onRename: (title) => widget.onRenameTab(id, title),
          onDragStarted: () => widget.onDragStart(id),
          onDragEnd: widget.onDragEnd,
          onDetach: detachable
              ? () => widget.onAction(TabAction.detachToWindow, id)
              : null,
        ),
      );
    }
    if (_dropIndex == ids.length) children.add(_indicator(context));
    return children;
  }

  Widget _indicator(BuildContext context) => Container(
    key: const Key('dropIndicator'),
    width: 2,
    height: 30,
    margin: const EdgeInsets.only(top: 8, left: 2, right: 2),
    decoration: BoxDecoration(
      color: context.c.accent,
      borderRadius: BorderRadius.circular(1),
    ),
  );

  /// The visible "+" new-tab button (ADR 0036 D1). Triggers the SAME
  /// new-session launcher as double-tapping empty strip space — it does NOT
  /// silently create a blank session or persist anything.
  Widget _newTabButton(BuildContext context) {
    final c = context.c;
    return IconButton(
      key: Key('newTab_${widget.group.id}'),
      tooltip: 'Yeni sekme (⌘T)',
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(Icons.add, color: c.textMuted),
      onPressed: widget.onNewTab,
    );
  }

  /// The visible split-right button (ADR 0036 D6). Mirrors ⌘\ + the "Sağa Böl"
  /// context-menu item; disabled (greyed) when the active group has <2 tabs.
  Widget _splitButton(BuildContext context) {
    final c = context.c;
    final enabled = widget.canSplit;
    return IconButton(
      key: Key('splitRight_${widget.group.id}'),
      tooltip: 'Sağa böl (⌘\\)',
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        Icons.vertical_split_outlined,
        color: enabled ? c.textMuted : c.textDim,
      ),
      onPressed: enabled ? widget.onSplitRight : null,
    );
  }

  /// Fade the scrolling region's leading/trailing edge while it overflows
  /// (ADR 0036 D7) so off-screen tabs are hinted. The leading fade is dropped at
  /// the very start and the trailing fade at the very end (nothing hidden there).
  Widget _edgeFade(BuildContext context, Widget child) {
    if (!_overflowing) return child;
    final max = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final fadeLeading = _scrollOffset > 0.5;
    final fadeTrailing = _scrollOffset < max - 0.5;
    if (!fadeLeading && !fadeTrailing) return child;
    const w = 16.0;
    return ShaderMask(
      shaderCallback: (rect) {
        final stops = <double>[0, 0, 1, 1];
        final colors = <Color>[
          fadeLeading ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          fadeTrailing ? Colors.transparent : Colors.black,
        ];
        final lead = (w / rect.width).clamp(0.0, 0.49);
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
          stops: [stops[0], lead, 1 - lead, stops[3]],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }

  Widget _moreButton(BuildContext context) {
    final c = context.c;
    final ids = _ids;
    return PopupMenuButton<String>(
      key: Key('tabOverflow_${widget.group.id}'),
      tooltip: 'Tüm sekmeler',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.keyboard_arrow_down, size: 18, color: c.textMuted),
      onSelected: widget.onSelect,
      itemBuilder: (_) => [
        for (final id in ids)
          PopupMenuItem<String>(
            value: id,
            height: 36,
            child: Row(
              children: [
                Icon(
                  iconForTabKind(widget.tabs[id]!.kind),
                  size: 13,
                  color: c.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.tabs[id]!.effectiveTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.ui(size: 12.5),
                  ),
                ),
                if (id == widget.group.activeTabId) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 14, color: c.accent),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
