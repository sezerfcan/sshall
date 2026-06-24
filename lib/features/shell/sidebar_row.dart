import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import 'shell_metrics.dart';
import 'sidebar_drag.dart';

/// A single consistent interaction primitive for every clickable sidebar tree
/// row (ADR 0030 D5/D6): host rows, folder rows, the Local Docker node. It
/// replaces the ad-hoc `GestureDetector` / `InkWell` mix with one widget that
/// carries the full set of desktop affordances:
///
/// - hover fill + click cursor ([MouseRegion] / [SystemMouseCursors.click]),
/// - pressed feedback,
/// - a SELECTED state (soft accent background + accent text) that is visually
///   distinct from hover — this is what finally reflects
///   `selectedConnectionProvider` in the tree (the #1 HIGH bug, D5),
/// - a VISIBLE keyboard focus ring (D6),
/// - an optional [revealedTrailing] (e.g. the kebab `…` overflow menu) shown
///   only on hover/focus so the row stays clean otherwise (don't regress that).
///
/// Drag-and-drop (ADR 0035 D1) is built INTO this primitive so there is a single
/// source of visual state. When [dragData] is set the whole row becomes a
/// [Draggable] (with a ~6px movement threshold so a short click still fires
/// [onTap]). When any of [onDropBefore]/[onDropAfter]/[onDropInto] is set the row
/// becomes a [DragTarget] with a 3-zone hit test (before / after / into):
/// before/after draw a 2px accent INSERTION LINE at the target depth, while a
/// folder's middle band draws a DISTINCT move-into highlight (accent outline +
/// soft fill) — never the same visual as [selected].
///
/// The caller supplies the row's inner content via [child]; this widget owns the
/// padding, background, cursor, focus ring, the reveal-on-hover slot and the
/// drag/drop visuals. When [selected] is true, descendants can read
/// [SidebarRowState.of] to tint their own text/icons to the accent.
class SidebarRow extends StatefulWidget {
  const SidebarRow({
    super.key,
    required this.onTap,
    required this.child,
    this.indent = ShellMetrics.sidebarBaseIndent,
    this.selected = false,
    this.revealedTrailing,
    this.semanticLabel,
    this.rowKey,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.dragData,
    this.dragGhostLabel,
    this.dragGhostIcon,
    this.isFolderRow = false,
    this.dndEnabled = true,
    this.onDropBefore,
    this.onDropAfter,
    this.onDropInto,
    this.willAcceptDrag,
    this.onDragStarted,
    this.onDragUpdateGlobal,
    this.onDragEnded,
  });

  final VoidCallback onTap;
  final Widget child;
  final double indent;
  final bool selected;

  /// Trailing widget revealed only on hover/focus (e.g. the `…` kebab menu).
  final Widget? revealedTrailing;
  final String? semanticLabel;

  /// Key applied to the row's tappable surface (kept as the existing row keys,
  /// e.g. `Key('host-$id')`, so tests/keys do not change).
  final Key? rowKey;

  /// Double-click = connect for host rows (ADR 0035 D4); null leaves it unbound.
  final VoidCallback? onDoubleTap;

  /// Right-click (secondary tap) opens the row's context menu (ADR 0035 D4).
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  // --- Drag-and-drop (ADR 0035 D1) ---

  /// When non-null AND [dndEnabled], the row is draggable carrying this payload.
  final SidebarDragData? dragData;

  /// Label + icon for the translucent compact drag-ghost chip.
  final String? dragGhostLabel;
  final IconData? dragGhostIcon;

  /// Whether THIS row is a folder (enables the middle move-into zone).
  final bool isFolderRow;

  /// Master switch for drag/drop on this row. The sidebar passes `false` while a
  /// search query is active (visible order is filtered, not canonical — D1).
  final bool dndEnabled;

  /// Drop callbacks; supplying any makes the row a [DragTarget]. They receive the
  /// dragged payload so the caller routes it to the right pure op.
  final void Function(SidebarDragData data)? onDropBefore;
  final void Function(SidebarDragData data)? onDropAfter;
  final void Function(SidebarDragData data)? onDropInto;

  /// Optional gate: returns false to REJECT a drag over this row (no indicator,
  /// no drop) — used to reject a folder dropped into its own descendant
  /// (`wouldCreateCycle`). Defaults to accept.
  final bool Function(SidebarDragData data, DropZone zone)? willAcceptDrag;

  /// Drag lifecycle hooks so the sidebar can drive edge auto-scroll
  /// ([EdgeDraggingAutoScroller]) with the live pointer position (ADR 0035 D1).
  final VoidCallback? onDragStarted;
  final void Function(Offset globalPosition)? onDragUpdateGlobal;
  final VoidCallback? onDragEnded;

  @override
  State<SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<SidebarRow> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  /// The live drop zone while a drag hovers this row (null = none).
  DropZone? _dropZone;

  /// Keys the DragTarget's child so its RenderBox can resolve the drop zone
  /// independent of ancestor layout (3-zone math).
  final GlobalKey _dropKey = GlobalKey();

  /// Pointer-event timestamp of the last tap-up, for manual double-click
  /// detection (D4). Uses the pointer event's own [Duration] timeStamp (which
  /// honors the test fake-clock) rather than DateTime.now, so the disambiguation
  /// is deterministic in widget tests too.
  Duration? _lastTapStamp;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  /// Records the up-event time; [onTap] then decides single vs double.
  void _markTapUp(PointerUpEvent e) {
    final last = _lastTapStamp;
    final isDouble =
        widget.onDoubleTap != null &&
        last != null &&
        (e.timeStamp - last) <= _doubleTapWindow;
    _lastTapStamp = isDouble ? null : e.timeStamp;
    _pendingDouble = isDouble;
  }

  bool _pendingDouble = false;

  void _handleTap() {
    if (_pendingDouble) {
      _pendingDouble = false;
      widget.onDoubleTap!();
      return;
    }
    widget.onTap();
  }

  bool get _isDragSource => widget.dragData != null && widget.dndEnabled;

  bool get _isDropTarget =>
      widget.dndEnabled &&
      (widget.onDropBefore != null ||
          widget.onDropAfter != null ||
          widget.onDropInto != null);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = widget.selected;

    final Color bg;
    if (selected) {
      bg = c.accentSoft; // distinct, soft accent background.
    } else if (_pressed) {
      bg = c.accent.withValues(alpha: 0.14);
    } else if (_hovered) {
      bg = c.accent.withValues(alpha: 0.07);
    } else {
      bg = Colors.transparent;
    }

    final reveal = _hovered || _focused;

    Widget row = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.indent,
        ShellMetrics.rowVerticalPadding,
        8,
        ShellMetrics.rowVerticalPadding,
      ),
      child: Row(
        children: [
          Expanded(child: widget.child),
          if (widget.revealedTrailing != null)
            AnimatedOpacity(
              duration: ShellMetrics.motionFast,
              opacity: reveal || selected ? 1 : 0,
              child: IgnorePointer(
                ignoring: !(reveal || selected),
                child: widget.revealedTrailing!,
              ),
            ),
        ],
      ),
    );

    // A move-into highlight is a DISTINCT treatment from selected: accent
    // outline + soft fill (selected is fill only). Reorder uses no fill — only
    // the insertion line below.
    final into = _dropZone == DropZone.into;
    final decoration = BoxDecoration(
      color: into ? c.accentSoft : bg,
      borderRadius: BorderRadius.circular(ShellMetrics.rowRadius),
      border: into
          ? Border.all(color: c.accent, width: 1.5)
          : (_focused ? Border.all(color: c.accent, width: 1.5) : null),
    );

    Widget surface = AnimatedContainer(
      duration: ShellMetrics.motionFast,
      curve: Curves.easeOut,
      decoration: decoration,
      child: row,
    );

    // Reorder insertion line: a 2px accent rule at the row's top (before) or
    // bottom (after) edge, inset to the TARGET depth so it reads at the level the
    // node will land at.
    if (_dropZone == DropZone.before || _dropZone == DropZone.after) {
      surface = Stack(
        children: [
          surface,
          Positioned(
            left: widget.indent,
            right: 4,
            top: _dropZone == DropZone.before ? 0 : null,
            bottom: _dropZone == DropZone.after ? 0 : null,
            child: Container(
              key: const Key('sidebar-insertion-line'),
              height: 2,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      );
    }

    Widget interactive = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Listener(
          // Capture the pointer up-event timeStamp BEFORE the tap recognizer
          // fires onTap, so [_handleTap] can disambiguate single vs double click
          // by timing rather than GestureDetector.onDoubleTap (which the row's
          // Draggable competes with in the gesture arena) — ADR 0035 D4.
          onPointerUp: widget.onDoubleTap == null ? null : _markTapUp,
          child: GestureDetector(
            key: widget.rowKey,
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: surface,
          ),
        ),
      ),
    );

    // Wrap as a DragTarget so a drag over this row computes the 3-zone intent and
    // routes the drop to the right callback. The indicator state lives here so it
    // shares the single visual source with hover/selected/focus.
    if (_isDropTarget) {
      interactive = _wrapDropTarget(interactive);
    }

    // Wrap as a Draggable so the whole row can be picked up. Flutter's default
    // touch-slop (~kPrecisePointerPanSlop on a mouse) gives the ~6px movement
    // threshold ADR 0035 D1/C2 asks for, so a click below the slop still fires
    // onTap (selection / connect) instead of starting a drag.
    if (_isDragSource) {
      interactive = _wrapDraggable(interactive, c.accent);
    }

    return SidebarRowState(
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Semantics(
          button: true,
          selected: selected,
          label: widget.semanticLabel,
          child: interactive,
        ),
      ),
    );
  }

  Widget _wrapDraggable(Widget child, Color accent) {
    final data = widget.dragData!;
    final ghost = _DragGhost(
      label: widget.dragGhostLabel ?? widget.semanticLabel ?? '',
      icon:
          widget.dragGhostIcon ??
          (data.isFolder ? Icons.folder_outlined : Icons.dns_outlined),
    );
    return Draggable<SidebarDragData>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Opacity(opacity: 0.85, child: ghost),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      onDragStarted: widget.onDragStarted,
      onDragUpdate: widget.onDragUpdateGlobal == null
          ? null
          : (d) => widget.onDragUpdateGlobal!(d.globalPosition),
      onDragEnd: (_) => widget.onDragEnded?.call(),
      onDraggableCanceled: (_, __) => widget.onDragEnded?.call(),
      child: child,
    );
  }

  /// Resolves the [DropZone] for a drag at the given global [offset], using the
  /// row's own RenderBox (keyed) so the math is independent of any ancestor
  /// layout. Returns null when the box is not laid out yet.
  DropZone? _zoneAt(Offset offset) {
    final box = _dropKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(offset);
    return zoneFor(local.dy, box.size.height, isFolder: widget.isFolderRow);
  }

  Widget _wrapDropTarget(Widget child) {
    return DragTarget<SidebarDragData>(
      onWillAcceptWithDetails: (details) {
        // Never accept dropping a node onto itself.
        if (details.data.id == widget.dragData?.id) return false;
        return true;
      },
      onMove: (details) {
        final zone = _zoneAt(details.offset);
        if (zone == null) return;
        // Respect the cycle gate: reject (no indicator) on a disallowed drop.
        final accept = widget.willAcceptDrag?.call(details.data, zone) ?? true;
        final next = accept ? zone : null;
        if (next != _dropZone) setState(() => _dropZone = next);
      },
      onLeave: (_) {
        if (_dropZone != null) setState(() => _dropZone = null);
      },
      onAcceptWithDetails: (details) {
        // Recompute from the drop position so the accept never depends on a
        // stale onMove (which may not have fired in a fast test gesture).
        final zone = _zoneAt(details.offset) ?? _dropZone;
        setState(() => _dropZone = null);
        if (zone == null) return;
        final accept = widget.willAcceptDrag?.call(details.data, zone) ?? true;
        if (!accept) return;
        switch (zone) {
          case DropZone.before:
            widget.onDropBefore?.call(details.data);
          case DropZone.after:
            widget.onDropAfter?.call(details.data);
          case DropZone.into:
            widget.onDropInto?.call(details.data);
        }
      },
      builder: (context, _, __) => KeyedSubtree(key: _dropKey, child: child),
    );
  }
}

/// The translucent compact chip shown under the pointer while dragging a tree
/// row (ADR 0035 D1): a tokenized icon + label so the user sees what they hold.
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.elevated,
          borderRadius: BorderRadius.circular(ShellMetrics.rowRadius),
          border: Border.all(color: c.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c.accent),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ui(size: 12.5, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inherited marker so a row's content widgets can tint themselves to the accent
/// when the row is selected, without each call-site threading a bool.
class SidebarRowState extends InheritedWidget {
  const SidebarRowState({
    super.key,
    required this.selected,
    required super.child,
  });

  final bool selected;

  static bool of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<SidebarRowState>();
    return w?.selected ?? false;
  }

  @override
  bool updateShouldNotify(SidebarRowState oldWidget) =>
      selected != oldWidget.selected;
}
