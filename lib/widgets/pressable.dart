import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';

/// The single shared desktop interaction primitive (ADR 0040 D3).
///
/// It generalizes the pattern the shell rows (`SidebarRow` / `RailItem`,
/// ADR 0030) already ship — [FocusableActionDetector] + hover/pressed/focus +
/// a visible keyboard focus ring + Enter/Space activation — so every clickable
/// shared widget (buttons, the toggle) speaks the SAME interaction language
/// instead of each rolling its own `GestureDetector` + `Opacity`.
///
/// What it owns:
/// - **states** rest / hover / pressed / focus / disabled / selected, with the
///   precedence `disabled > pressed > selected > hover > focus > rest`;
/// - **focus is ALWAYS additive** — the ring is composited OVER whatever fill
///   the lower state produced (selected+focus = selectedBg + ring), never
///   replacing it;
/// - **hover only for pointers** (`onShowHoverHighlight`), **ring only on
///   keyboard/AT focus** (`onShowFocusHighlight`) — a pointer-focus shows no
///   ring;
/// - **Enter AND Space** both activate (`ActivateIntent` + a Space activator);
/// - a **2px OFFSET focus ring** in the dedicated `focusRing` token, radius
///   matching the control;
/// - a **click cursor**, and a **≥44px minimum hit target** that enlarges the
///   HIT AREA only — the painted [child] is never resized, so at-rest paint is
///   pixel-stable.
///
/// The state overlay is a translucent wash composited over the child (clipped to
/// [borderRadius]); the child keeps painting its own fill, so a button/toggle's
/// rest appearance is unchanged and only gains the additive hover/pressed wash.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.semanticLabel,
    this.isToggle = false,
    this.toggledState,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.md8)),
    this.minTarget = kMinTapTarget,
    this.focusNode,
    this.autofocus = false,
    this.behaviorKey,
    this.addSemantics = true,
  });

  /// The painted control. Its own size/decoration are preserved; this widget
  /// only adds the interaction overlay + ring + a larger transparent hit box.
  final Widget child;

  /// Activation callback. `null` => disabled (no hover/pressed/focus effect,
  /// Enter/Space/tap are no-ops, cursor is basic, child dimmed to [disabledFg]
  /// intent).
  final VoidCallback? onPressed;

  /// Selected/checked visual state (soft accent fill, == sidebar selected row).
  final bool selected;

  /// Accessible name exposed to screen readers.
  final String? semanticLabel;

  /// When true the control is announced as a switch (toggle) carrying
  /// [toggledState]; otherwise it is announced as a button.
  final bool isToggle;
  final bool? toggledState;

  /// Radius of the focus ring + state overlay clip; match the control's shape.
  final BorderRadius borderRadius;

  /// Minimum interactive target (WCAG 2.5.5/2.5.8). Enlarges the HIT AREA, not
  /// the painted size.
  final double minTarget;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Optional key applied to the inner gesture surface (kept stable for tests).
  final Key? behaviorKey;

  /// Whether this widget emits its own button/toggle [Semantics] node. Callers
  /// that own a more specific semantics wrapper (e.g. AppToggle, which keeps its
  /// existing label+toggled node) pass `false`.
  final bool addSemantics;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = widget.selected;

    // State fill precedence: disabled > pressed > selected > hover > focus(rest
    // fill). Focus does NOT contribute a fill — it is the additive ring drawn on
    // top, so it never replaces the lower state's fill.
    Color overlay;
    if (!_enabled) {
      overlay = Colors.transparent;
    } else if (_pressed) {
      overlay = c.pressedOverlay;
    } else if (selected) {
      overlay = c.selectedBg;
    } else if (_hovered) {
      overlay = c.hoverOverlay;
    } else {
      overlay = Colors.transparent;
    }

    // The painted child, with the additive state wash composited over it and the
    // keyboard focus ring on top (2px offset).
    Widget painted = Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        // State wash — clipped to the control shape, drawn over the child fill.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: overlay,
                borderRadius: widget.borderRadius,
              ),
            ),
          ),
        ),
        // 2px OFFSET focus ring — only on keyboard/AT focus, additive (drawn on
        // top of any state). Instant (no animation) per D3.
        if (_focused && _enabled)
          Positioned(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: _ringRadius(widget.borderRadius),
                  border: Border.all(color: c.focusRing, width: 2.0),
                ),
              ),
            ),
          ),
      ],
    );

    // Disabled dim — keep the ~0.5 intent of the old `Opacity(0.5)` so at-rest
    // disabled paint is unchanged.
    if (!_enabled) {
      painted = Opacity(opacity: 0.5, child: painted);
    }

    // Hover + keyboard activation live AROUND the painted child (their bounds =
    // the painted size, which is exactly right for hover/focus).
    final interactive = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: _enabled,
      mouseCursor: _enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      // Ring only on keyboard/AT focus — pointer focus reports false here.
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: MouseRegion(
        // Hover is POINTER-only (a MouseRegion, exactly like the shell
        // SidebarRow), so it is deterministic and never fires for keyboard focus.
        onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: _enabled
            ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
            : null,
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: painted,
      ),
    );

    // [_HitTarget] is the OUTERMOST render object so NOTHING above it gates the
    // overflow hits: its LAYOUT size equals the painted child (never pushes
    // siblings — at-rest layout pixel-stable), but it ACCEPTS pointer taps within
    // a centered minSize (>=44px) region (WCAG 2.5.5/2.5.8). It owns the tap +
    // pressed-state for the whole control.
    final body = widget.addSemantics
        ? Semantics(
            container: true,
            button: !widget.isToggle,
            toggled: widget.isToggle ? widget.toggledState : null,
            enabled: _enabled,
            label: widget.semanticLabel,
            onTap: _enabled ? _activate : null,
            child: interactive,
          )
        : interactive;

    return _HitTarget(
      key: widget.behaviorKey,
      minSize: widget.minTarget,
      onTap: _enabled ? _activate : null,
      onTapDown: _enabled ? () => setState(() => _pressed = true) : null,
      onTapRelease: _enabled ? () => setState(() => _pressed = false) : null,
      child: body,
    );
  }

  /// The ring sits 2px outside the control, so its corners read slightly larger
  /// than the control's own radius.
  BorderRadius _ringRadius(BorderRadius r) => BorderRadius.only(
    topLeft: r.topLeft + const Radius.circular(2),
    topRight: r.topRight + const Radius.circular(2),
    bottomLeft: r.bottomLeft + const Radius.circular(2),
    bottomRight: r.bottomRight + const Radius.circular(2),
  );
}

/// A render-object widget whose LAYOUT size is exactly its child's, but whose
/// HIT TEST region is enlarged to a centered [minSize] square — so a small
/// control (a 38px icon button, a 23px toggle track) becomes an easy ≥44px
/// target WITHOUT pushing siblings or changing any at-rest pixel (the whole
/// premise of pass-1).
class _HitTarget extends SingleChildRenderObjectWidget {
  const _HitTarget({
    super.key,
    required Widget super.child,
    required this.minSize,
    this.onTap,
    this.onTapDown,
    this.onTapRelease,
  });

  final double minSize;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapRelease;

  @override
  _RenderHitTarget createRenderObject(BuildContext context) => _RenderHitTarget(
    minSize: minSize,
    onTap: onTap,
    onTapDown: onTapDown,
    onTapRelease: onTapRelease,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderHitTarget renderObject) {
    renderObject
      ..minSize = minSize
      ..onTap = onTap
      ..onTapDown = onTapDown
      ..onTapRelease = onTapRelease;
  }
}

class _RenderHitTarget extends RenderProxyBox {
  _RenderHitTarget({
    required double minSize,
    this.onTap,
    this.onTapDown,
    this.onTapRelease,
  }) : _minSize = minSize {
    _tap = TapGestureRecognizer(debugOwner: this)
      ..onTapDown = ((_) => onTapDown?.call())
      ..onTapUp = ((_) {
        onTapRelease?.call();
        onTap?.call();
      })
      ..onTapCancel = (() => onTapRelease?.call());
  }

  double _minSize;
  set minSize(double v) {
    if (v == _minSize) return;
    _minSize = v;
    markNeedsLayout();
  }

  VoidCallback? onTap;
  VoidCallback? onTapDown;
  VoidCallback? onTapRelease;

  late final TapGestureRecognizer _tap;

  bool get _enabled => onTap != null;

  /// The centered, enlarged hit rectangle (>= child size, >= minSize).
  Rect get _hitRect {
    final w = _minSize > size.width ? _minSize : size.width;
    final h = _minSize > size.height ? _minSize : size.height;
    final dx = (size.width - w) / 2;
    final dy = (size.height - h) / 2;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  // Claim the pointer ourselves so the tap recognizer fires for in-bounds hits
  // too (RenderProxyBox returns false here by default, which would route the tap
  // only to descendants — and we have no descendant recognizer).
  @override
  bool hitTestSelf(Offset position) => _enabled && _hitRect.contains(position);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_enabled) {
      return super.hitTest(result, position: position);
    }
    // In-bounds: the normal proxy hit test descends to the child (hover/cursor)
    // and adds us once (via hitTestSelf).
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    // Overflow region (>=minSize, outside the painted bounds): no child lives
    // here, so we claim it for ourselves — extending the tap target without any
    // layout change.
    if (_hitRect.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (_enabled && event is PointerDownEvent) {
      _tap.addPointer(event);
    }
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }
}
