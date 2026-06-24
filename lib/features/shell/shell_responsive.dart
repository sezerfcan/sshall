/// Adaptive-shell breakpoints and helpers (ADR 0021).
///
/// Every magic number that drives the shell's responsive collapse lives here so
/// the behaviour stays consistent and tunable in one place. Title-bar thresholds
/// are expressed in **window width** (the title bar spans the full window);
/// tab-strip thresholds are in **panel width** (a single split panel, measured
/// with a `LayoutBuilder`). All members are pure so they are unit-tested without
/// pumping widgets.
library;

/// Width breakpoints (logical px) for the title bar chrome.
class ShellBreakpoints {
  ShellBreakpoints._();

  /// Width (logical px) of the gutter reserved on the left of the title bar for
  /// the native macOS traffic lights (ADR 0024/0039). Centralized here as a
  /// single named source — the title bar reads it instead of a magic literal so
  /// the value never drifts. When the traffic lights are hidden (fullscreen)
  /// the gutter collapses to zero via [macTrafficLightGutter].
  static const double kMacTrafficLightGutter = 78;

  /// The traffic-light gutter for the current window state. In fullscreen macOS
  /// hides the traffic lights, so the gutter collapses to 0 and the brand may
  /// slide back to the leading edge; otherwise the full [kMacTrafficLightGutter]
  /// is reserved. Pure → unit-tested without pumping a window.
  static double macTrafficLightGutter({required bool isFullScreen}) =>
      isFullScreen ? 0 : kMacTrafficLightGutter;

  /// Below this window width the title-bar version label is hidden.
  static const double titleVersionHide = 940;

  /// Below this window width the centered active-session title is hidden (it is
  /// the second thing sacrificed after the version badge — ADR 0039 D5). Above
  /// it, the title renders (middle-ellipsized) between brand and trailing.
  static const double titleHide = 880;

  /// Below this window width the Settings gear folds into the "⋯" overflow menu
  /// (ADR 0039 D5). The gear is sacrificed BEFORE the theme + help controls, so
  /// this threshold sits ABOVE [titleOverflow] (where the WHOLE trailing cluster
  /// collapses). Everything stays reachable in the overflow (§9).
  static const double titleSettingsHide = 840;

  /// Below this window width the theme swatches + keyboard-help button collapse
  /// into a single "⋯" overflow menu. Everything stays reachable there (§9). At
  /// exactly this width the toolbar is still inline (so the 800px widget tests
  /// keep finding the inline controls).
  static const double titleOverflow = 800;

  /// Below this window width the "sshall" wordmark is hidden (icon only). Not
  /// reachable by resizing (min window width is 720) but kept defensive and
  /// unit-tested so the chrome degrades gracefully at any width.
  static const double titleWordmarkHide = 500;

  // Note: the title-bar staging thresholds above are deliberately spaced at
  // least 40px apart (version 940 → title 880 → settings 840 → overflow 800),
  // far wider than any single-pixel resize jitter, so no boundary flicker is
  // possible and an explicit hysteresis band is unnecessary (ADR 0039 D5).

  static bool showVersion(double windowWidth) =>
      windowWidth >= titleVersionHide;

  /// Whether the centered active-session title should render at [windowWidth].
  /// (Only matters when a session is active — the home surface shows nothing.)
  static bool showTitle(double windowWidth) => windowWidth >= titleHide;

  /// Whether the Settings gear has folded into the "⋯" overflow (it goes BEFORE
  /// theme/help — D5 ladder). True ⇒ Settings lives in the overflow menu.
  static bool titleSettingsOverflow(double windowWidth) =>
      windowWidth < titleSettingsHide;

  static bool titleNeedsOverflow(double windowWidth) =>
      windowWidth < titleOverflow;

  static bool showWordmark(double windowWidth) =>
      windowWidth >= titleWordmarkHide;
}

/// How a tab pill should render given the width of the panel it lives in.
class TabPillMode {
  /// When true the pill renders as just its kind icon; the title moves to the
  /// pill's tooltip (kept discoverable — §9) and ✕ still appears on hover/active.
  final bool iconOnly;

  /// Max width (logical px) for the title text when [iconOnly] is false.
  final double maxTitleWidth;

  const TabPillMode(this.iconOnly, this.maxTitleWidth);
}

/// Pick a [TabPillMode] for a panel of [panelWidth]. As a split panel narrows,
/// titles shrink, then pills drop to icon-only. Pure → unit-tested.
TabPillMode tabPillMode(double panelWidth) {
  if (panelWidth < 200) return const TabPillMode(true, 0);
  if (panelWidth < 260) return const TabPillMode(false, 56);
  if (panelWidth < 360) return const TabPillMode(false, 84);
  if (panelWidth < 460) return const TabPillMode(false, 120);
  return const TabPillMode(false, 160);
}

/// How far (logical px) beyond the window's content bounds a tab must be
/// released to tear it off into a separate OS window (ADR 0021 drag-to-detach,
/// extending ADR 0020). A small positive inset avoids accidental detaches from
/// drops that land right on the window border.
const double kDetachEdgeThreshold = 8;
