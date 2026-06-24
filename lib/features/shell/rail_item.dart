import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import 'shell_metrics.dart';

/// A single mutually-distinct interaction primitive for the left rail
/// (ADR 0030 D3/D6). One widget for both destination items and the
/// show/hide control, so identical affordances (hover/focus/cursor) stay
/// consistent.
///
/// Visual states (must be mutually distinct):
/// - rest:   transparent fill, muted icon ([AppColors.textMuted]).
/// - hover:  ~10% accent fill, un-muted icon ([AppColors.text]).
/// - active: a 3px left accent bar (when [showActiveBar]) + accent icon, on
///           top of a soft accent fill.
///
/// The show/hide TOGGLE is a control, not a "place", so it passes
/// [showActiveBar] = false: it still gets an active fill when the sidebar is
/// visible, but never the left destination bar.
class RailItem extends StatefulWidget {
  const RailItem({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    required this.semanticLabel,
    this.showActiveBar = true,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final String semanticLabel;

  /// Destination items show the 3px left accent bar when active; controls
  /// (the show/hide toggle) do not (ADR 0030 D3).
  final bool showActiveBar;

  @override
  State<RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<RailItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final active = widget.active;

    final Color fill;
    final Color iconColor;
    if (active) {
      fill = c.accentSoft;
      iconColor = c.accent;
    } else if (_hovered) {
      // ~10% foreground/accent fill + un-muted icon.
      fill = c.accent.withValues(alpha: 0.10);
      iconColor = c.text;
    } else {
      fill = Colors.transparent;
      iconColor = c.textMuted;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShellMetrics.railItemGap),
      child: Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        // Tooltip on the right side of the icon (ADR 0030 D7).
        verticalOffset: 0,
        margin: const EdgeInsets.only(left: ShellMetrics.railWidth),
        child: Semantics(
          button: true,
          selected: active,
          label: widget.semanticLabel,
          child: FocusableActionDetector(
            onShowHoverHighlight: (v) => setState(() => _hovered = v),
            onShowFocusHighlight: (v) => setState(() => _focused = v),
            mouseCursor: SystemMouseCursors.click,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onTap();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: ShellMetrics.railWidth,
                height: ShellMetrics.railItemSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The active destination's left accent bar.
                    if (active && widget.showActiveBar)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: ShellMetrics.railActiveBarWidth,
                          height: ShellMetrics.railActiveBarHeight,
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: ShellMetrics.motionFast,
                      curve: Curves.easeOut,
                      width: ShellMetrics.railItemSize,
                      height: ShellMetrics.railItemSize,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(
                          ShellMetrics.railItemRadius,
                        ),
                        // Visible keyboard focus ring (D6).
                        border: _focused
                            ? Border.all(color: c.accent, width: 1.5)
                            : null,
                      ),
                      child: Icon(
                        widget.icon,
                        size: ShellMetrics.railIconSize,
                        color: iconColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
