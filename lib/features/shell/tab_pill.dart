import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/context_ext.dart';
import '../terminal/session_status.dart';
import '../terminal/status_colors.dart';
import 'shell_responsive.dart';
import 'shell_state.dart';

/// Icon for a tab kind. Shared by [TabPill] and the overflow ("more") menu.
IconData iconForTabKind(TabKind k) => switch (k) {
  TabKind.terminal => Icons.terminal_outlined,
  TabKind.sftp => Icons.sync_alt,
};

/// A single VS Code-style tab pill: `[icon] [title] [status dot / close ✕]`.
///
/// Behaviour (ADR 0018):
/// - single click → [onSelect]; middle click → [onClose] (if closable);
///   right click → [onContextMenu] with the global pointer position.
/// - close ✕ shows on hover or on the active tab; a live session shows a status
///   dot when not hovered (the "dirty" indicator that becomes ✕ on hover).
/// - pinned tabs render compact (icon only, no ✕).
/// - the whole pill is a [Draggable] for reorder / move / split.
class TabPill extends StatefulWidget {
  final ShellTab tab;
  final bool active;
  final bool isActiveGroup;
  final String sourceGroupId;

  /// Live session status for terminal tabs; null for SFTP. Drives the status
  /// dot (green/amber/red/dim per ADR 0032 D8).
  final ValueListenable<SessionStatus>? sessionStatus;

  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(Offset globalPosition) onContextMenu;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  /// Commit a new manual title (ADR 0036 D2). Null disables inline rename
  /// (double-click on the title) so the pill stays backward-compatible. A blank
  /// value clears the manual title back to the derived default (handled by the
  /// controller's setTabTitle).
  final void Function(String newTitle)? onRename;

  /// Tear the tab off into a separate OS window when it is dragged beyond the
  /// window bounds (ADR 0021). Null when the tab is not detachable (management
  /// tabs, or multi-window unsupported) — drag-out then just cancels as before.
  final VoidCallback? onDetach;

  /// When true the pill renders compact (icon only); the title is exposed via
  /// the pill's tooltip. Driven by the panel width (ADR 0021).
  final bool iconOnly;

  /// Max width for the title text (logical px) when not [iconOnly]. Shrinks as
  /// the panel narrows.
  final double maxTitleWidth;

  const TabPill({
    super.key,
    required this.tab,
    required this.active,
    required this.isActiveGroup,
    required this.sourceGroupId,
    required this.onSelect,
    required this.onClose,
    required this.onContextMenu,
    required this.onDragStarted,
    required this.onDragEnd,
    this.sessionStatus,
    this.onDetach,
    this.onRename,
    this.iconOnly = false,
    this.maxTitleWidth = 160,
  });

  @override
  State<TabPill> createState() => _TabPillState();
}

class _TabPillState extends State<TabPill> {
  bool _hovered = false;

  /// True while the pointer is past the window edge mid-drag — drives the
  /// "release to detach" hint in the drag feedback (ADR 0021, §9).
  final ValueNotifier<bool> _nearEdge = ValueNotifier<bool>(false);

  /// Inline rename state (ADR 0036 D2). Non-null while the title is being edited
  /// in place; carries the editing controller + focus node.
  TextEditingController? _editController;
  FocusNode? _editFocus;
  bool get _editing => _editController != null;

  @override
  void dispose() {
    _nearEdge.dispose();
    _editController?.dispose();
    _editFocus?.dispose();
    super.dispose();
  }

  /// Enter inline rename: prefill with the effective title and select all so
  /// typing replaces it. Enter / blur commit; Esc cancels (ADR 0036 D2).
  void _startEditing() {
    if (widget.onRename == null || _editing) return;
    final text = widget.tab.effectiveTitle;
    final ctrl = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    final focus = FocusNode();
    setState(() {
      _editController = ctrl;
      _editFocus = focus;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _commitEditing() {
    final ctrl = _editController;
    if (ctrl == null) return;
    final value = ctrl.text;
    _stopEditing();
    widget.onRename?.call(value);
  }

  void _cancelEditing() => _stopEditing();

  void _stopEditing() {
    final ctrl = _editController;
    final focus = _editFocus;
    setState(() {
      _editController = null;
      _editFocus = null;
    });
    // Dispose after the frame so the detached TextField/Focus unmounts cleanly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl?.dispose();
      focus?.dispose();
    });
  }

  /// Whether [globalPos] is beyond the window's content bounds (so releasing
  /// there should tear the tab into a new OS window — ADR 0021). Uses the live
  /// window size from [MediaQuery]; returns false if unavailable.
  bool _isOutsideWindow(Offset globalPos) {
    final size = MediaQuery.maybeOf(context)?.size;
    if (size == null) return false;
    const t = kDetachEdgeThreshold;
    return globalPos.dx < -t ||
        globalPos.dy < -t ||
        globalPos.dx > size.width + t ||
        globalPos.dy > size.height + t;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        // Middle-click closes the tab (if closable). Listener is passive so it
        // never competes with the tap/drag recognizers below.
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) widget.onClose();
        },
        child: Draggable<TabDragData>(
          data: TabDragData(widget.tab.id, widget.sourceGroupId),
          // Anchor the feedback at the pointer so the strip's DragTarget can use
          // details.offset as the true cursor position for insertion math.
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () {
            _nearEdge.value = false;
            widget.onDragStarted();
          },
          // Track edge proximity only for detachable tabs (the hint + tear-off).
          onDragUpdate: widget.onDetach == null
              ? null
              : (d) => _nearEdge.value = _isOutsideWindow(d.globalPosition),
          onDragEnd: (_) {
            _nearEdge.value = false;
            widget.onDragEnd();
          },
          // A canceled drag = not accepted by any in-app DragTarget. If it ended
          // outside the window and the tab is detachable, tear it off into a new
          // OS window (same path as the right-click "Ayrı Pencereye Taşı").
          onDraggableCanceled: (_, offset) {
            if (widget.onDetach != null && _isOutsideWindow(offset)) {
              widget.onDetach!();
            }
            _nearEdge.value = false;
            widget.onDragEnd();
          },
          feedback: _feedback(context),
          childWhenDragging: Opacity(opacity: 0.35, child: _body(context)),
          child: _interactive(context),
        ),
      ),
    );
  }

  Widget _interactive(BuildContext context) => Tooltip(
    message: widget.tab.effectiveTitle,
    waitDuration: const Duration(milliseconds: 600),
    child: GestureDetector(
      key: Key('tab_${widget.tab.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelect,
      onSecondaryTapDown: (d) => widget.onContextMenu(d.globalPosition),
      child: _body(context),
    ),
  );

  Widget _feedback(BuildContext context) {
    final c = context.c;
    final body = Material(
      type: MaterialType.transparency,
      child: Opacity(opacity: 0.9, child: _body(context, feedback: true)),
    );
    if (widget.onDetach == null) return body;
    // Show a "release to detach" badge below the dragged pill the moment the
    // pointer crosses the window edge.
    return ValueListenableBuilder<bool>(
      valueListenable: _nearEdge,
      child: body,
      builder: (_, near, child) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [child!, if (near) _detachBadge(c)],
      ),
    );
  }

  Widget _detachBadge(AppColors c) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.open_in_new, size: 12, color: c.bg),
          const SizedBox(width: 5),
          Text(
            'Ayrı pencereye taşı',
            style: TextStyle(
              fontFamily: 'IBM Plex Sans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.bg,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context, {bool feedback = false}) {
    final c = context.c;
    final tab = widget.tab;
    final active = widget.active || feedback;
    final compact = tab.pinned;
    // Narrow-panel icon-only for a normal (non-pinned) tab: the title moves to
    // the pill's tooltip and ✕ / status stay reachable (ADR 0021, §9).
    final dense = widget.iconOnly && !compact;
    final accentTop = widget.isActiveGroup || feedback
        ? c.accent
        : c.borderStrong;

    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 6),
      child: Stack(
        children: [
          Container(
            height: 32,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 10)
                : dense
                ? const EdgeInsets.symmetric(horizontal: 8)
                : const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: active ? c.surface : Colors.transparent,
              border: Border.all(color: c.border),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconForTabKind(tab.kind),
                  size: 13,
                  color: active ? c.text : c.textMuted,
                ),
                if (compact) ...[
                  // Pinned keeps its identity (ADR 0036 D4): pin glyph + a short
                  // truncated title + the live status dot — never an anonymous
                  // icon, and never icon-only (the narrow-panel iconOnly mode is
                  // ignored for pinned). Closing stays via middle-click / menu,
                  // so no hover-✕ here.
                  const SizedBox(width: 5),
                  Icon(Icons.push_pin, size: 9, color: c.textDim),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 64),
                    child: Text(
                      tab.effectiveTitle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: context.ui(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: active ? c.text : c.textMuted,
                      ),
                    ),
                  ),
                  if (widget.sessionStatus != null) ...[
                    const SizedBox(width: 4),
                    _statusDot(context),
                  ],
                ] else if (dense) ...[
                  _denseTrailing(context),
                ] else ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: widget.maxTitleWidth),
                    child: _titleOrEditor(context, active),
                  ),
                  const SizedBox(width: 4),
                  _trailing(context),
                ],
              ],
            ),
          ),
          // Active tab: a 2px accent strip across the top (VS Code signature).
          if (active)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: accentTop,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The title region: the static title text, or — while [_editing] — an inline
  /// rename [TextField] (ADR 0036 D2). Double-clicking the title (when rename is
  /// enabled) opens the editor; Enter / blur commit, Esc cancels.
  Widget _titleOrEditor(BuildContext context, bool active) {
    final c = context.c;
    if (_editing) {
      return _RenameField(
        fieldKey: Key('renameField_${widget.tab.id}'),
        controller: _editController!,
        focusNode: _editFocus!,
        style: context.ui(size: 12.5, weight: FontWeight.w500, color: c.text),
        cursorColor: c.accent,
        onSubmitted: (_) => _commitEditing(),
        onCancel: _cancelEditing,
        onBlur: _commitEditing,
      );
    }
    final text = Text(
      widget.tab.effectiveTitle,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: context.ui(
        size: 12.5,
        weight: FontWeight.w500,
        color: active ? c.text : c.textMuted,
      ),
    );
    if (widget.onRename == null) return text;
    // Double-tap the title to rename in place. Detected with a PASSIVE Listener
    // (not a GestureDetector.onDoubleTap) so it never enters the gesture arena —
    // that would steal the single tap from the pill's selection / Draggable and
    // leave a pending double-tap timer after disposal. The outer pill keeps
    // single-tap selection and drag intact.
    return Listener(
      key: Key('renameTitle_${widget.tab.id}'),
      onPointerDown: _onTitlePointerDown,
      child: text,
    );
  }

  // Passive double-tap detection on the title (see _titleOrEditor).
  Duration? _lastTitleDownAt;
  Offset? _lastTitleDownPos;

  void _onTitlePointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryMouseButton && e.buttons != 0) return;
    final now = e.timeStamp;
    final near =
        _lastTitleDownPos != null &&
        (e.position - _lastTitleDownPos!).distance < kDoubleTapSlop;
    if (_lastTitleDownAt != null &&
        now - _lastTitleDownAt! < kDoubleTapTimeout &&
        near) {
      _lastTitleDownAt = null;
      _startEditing();
    } else {
      _lastTitleDownAt = now;
      _lastTitleDownPos = e.position;
    }
  }

  /// Icon-only (narrow panel) trailing: keep ✕ (hover) and the live status dot
  /// reachable, but reserve no space when idle so the pill stays minimal.
  Widget _denseTrailing(BuildContext context) {
    if (_hovered || widget.sessionStatus != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: _trailing(context),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _trailing(BuildContext context) {
    // Priority: hover → ✕; live session → dot; active tab → ✕; else gap.
    if (_hovered) return _closeButton(context);
    if (widget.sessionStatus != null) return _statusDot(context);
    if (widget.active) return _closeButton(context);
    return const SizedBox(width: 24, height: 24);
  }

  Widget _closeButton(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: 'Sekmeyi kapat (⌘W)',
      child: GestureDetector(
        key: Key('closeTab_${widget.tab.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Icon(
              Icons.close,
              size: 13,
              color: _hovered ? c.text : c.textDim,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusDot(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: ValueListenableBuilder<SessionStatus>(
          valueListenable: widget.sessionStatus!,
          builder: (_, s, __) {
            final dot = Container(
              key: Key('statusDot_${widget.tab.id}'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColorOf(s, c),
                shape: BoxShape.circle,
              ),
            );
            // Pulse the dot while connecting/authenticating (amber, D8) so the
            // in-progress state reads as live rather than stalled.
            if (statusPulses(s.state)) {
              return _PulsingDot(child: dot);
            }
            return dot;
          },
        ),
      ),
    );
  }
}

/// The inline rename editor (ADR 0036 D2): a compact, borderless [TextField]
/// sized to fit inside the pill. Enter (onSubmitted) commits, Esc cancels, and
/// losing focus (blur — e.g. clicking elsewhere) commits so an accidental
/// outside-tap keeps the typed value. Esc suppresses the blur-commit so cancel
/// truly discards.
class _RenameField extends StatefulWidget {
  const _RenameField({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.cursorColor,
    required this.onSubmitted,
    required this.onCancel,
    required this.onBlur,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final Color cursorColor;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final VoidCallback onBlur;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  // Set when Esc cancels (or Enter commits) so the focus-lost handler does not
  // fire a second, duplicate commit.
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus && !_resolved) {
      _resolved = true;
      widget.onBlur();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _resolved = true; // suppress the blur-commit that focus loss would cause.
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Focus(
        onKeyEvent: _onKey,
        child: TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: widget.style,
          cursorColor: widget.cursorColor,
          maxLines: 1,
          cursorHeight: 14,
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onSubmitted: (v) {
            _resolved = true;
            widget.onSubmitted(v);
          },
        ),
      ),
    );
  }
}

/// A subtle opacity pulse used by the connecting status dot (ADR 0032 D8).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.child});
  final Widget child;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_ctrl),
    child: widget.child,
  );
}
