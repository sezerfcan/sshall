import 'package:flutter/foundation.dart';

/// Centralized rail + sidebar layout/motion metrics and small interaction
/// helpers (ADR 0030 D8). Every magic number that drives the left-navigation
/// (rail widths, hit targets, paddings, icon sizes, radii, panel clamps and
/// motion durations) lives here so the two layers stay visually consistent and
/// tunable in one place — no more scattered `58` / `248` literals.
///
/// Pure constants + pure functions, so they are unit-testable without pumping
/// widgets.
class ShellMetrics {
  ShellMetrics._();

  // --- Rail (fixed icon mode-switcher; never resized) ---

  /// Fixed width of the [NavRail] (ADR 0030 D1; was 58).
  static const double railWidth = 52;

  /// Vertical padding inside the rail column.
  static const double railVerticalPadding = 12;

  /// Square hit target for a rail item / the sidebar toggle (ADR 0030 D3).
  static const double railItemSize = 40;

  /// Corner radius of a rail item's hover/active fill.
  static const double railItemRadius = 9;

  /// Vertical gap between successive rail items (~3px).
  static const double railItemGap = 3;

  /// Icon size inside a rail item.
  static const double railIconSize = 20;

  /// The active-destination left accent bar: 3px wide, ~22px tall, centered.
  static const double railActiveBarWidth = 3;
  static const double railActiveBarHeight = 22;

  /// Extra gap above the bottom (Vault/Settings) cluster's hairline divider.
  static const double railClusterGap = 8;

  // --- Connection sidebar (resizable detail panel) ---

  /// Default panel width (ADR 0030 D4; replaces the hard-coded 248).
  static const double sidebarDefaultWidth = 272;

  /// Hard clamp for the resizable panel width.
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidth = 480;

  /// Dragging the right edge below this width snaps the panel to collapsed.
  /// A hysteresis gap to [sidebarMinWidth] avoids flicker at the boundary.
  static const double sidebarCollapseSnap = 180;

  /// Width (logical px) of the invisible right-edge resize hit zone.
  static const double sidebarResizeHandleWidth = 7;

  /// Indent unit per tree depth level in the sidebar.
  static const double sidebarIndentStep = 14;

  /// Base horizontal inset for the sidebar tree's left padding.
  static const double sidebarBaseIndent = 8;

  /// Extra inset applied to a host row's content so it lines up under the
  /// folder disclosure chevron (the host row's indent + this offset).
  static const double hostRowIndent = 4;

  /// Extra inset for a Docker host's container sub-tree, nesting it one step
  /// under its host row (the host row's indent + this offset).
  static const double containerRowIndent = 18;

  /// Left inset for the always-visible Local Docker node's container sub-tree.
  /// Anchored at the tree base so it nests like a top-level host's containers
  /// ([sidebarBaseIndent] + [containerRowIndent]).
  static const double localContainerIndent =
      sidebarBaseIndent + containerRowIndent;

  // --- Shared sidebar row metrics ---

  static const double rowRadius = 7;
  static const double rowVerticalPadding = 6;
  static const double rowIconSize = 15;

  // --- Motion (120–180ms ease-out; the rail never animates position) ---

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionMed = Duration(milliseconds: 160);

  /// Clamp [width] into the resizable range. Use when applying a persisted or
  /// freshly-dragged width that must never escape [sidebarMinWidth,
  /// sidebarMaxWidth].
  static double clampSidebarWidth(double width) =>
      width.clamp(sidebarMinWidth, sidebarMaxWidth);
}

/// Returns the platform-appropriate modifier glyph for a primary shortcut:
/// `⌘` on macOS, `Ctrl` elsewhere. Centralized so rail tooltips and the
/// shortcuts-help dialog read consistently. The optional
/// [platform] argument keeps it unit-testable without a real host.
String primaryModifierGlyph([TargetPlatform? platform]) {
  final p = platform ?? defaultTargetPlatform;
  return p == TargetPlatform.macOS ? '⌘' : 'Ctrl';
}

/// Formats a destination shortcut for a rail tooltip, e.g. `"Bağlantılar  ⌘1"`
/// on macOS or `"Bağlantılar  Ctrl+1"` elsewhere (ADR 0030 D7, §9).
String railTooltip(String name, int digit, [TargetPlatform? platform]) {
  final glyph = primaryModifierGlyph(platform);
  final sep = glyph == '⌘' ? '' : '+';
  return '$name  $glyph$sep$digit';
}
