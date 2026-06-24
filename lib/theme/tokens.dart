/// # Design tokens (ADR 0040 — pass-1, PIXEL-STABLE)
///
/// The single import a UI author reaches for when they need a font size, a
/// padding, an icon size or a corner radius. Today these values were scattered
/// as ~22 ad-hoc literals across feature call-sites (`context.ui(size: 13)`,
/// `EdgeInsets.symmetric(horizontal: 15)`, `Icon(size: 16)`, …). This file gives
/// them NAMES so they can be adopted consistently.
///
/// ## Pass-1 guarantee: adopting a token role is PIXEL-IDENTICAL
///
/// Every role here is mapped to the CURRENT dominant value already in the app
/// (observed distribution: ui 13 = dominant body/button, 14/16 = titles,
/// 12.5/12 = labels, 11.5/11 = captions/overlines; mono 13 = body, 11.5 =
/// caption). So a widget that swaps a raw literal for the matching role renders
/// the exact same pixels. The real grid-snap of off-grid literals (15→16, 9→8)
/// and the full call-site font-size consolidation are PASS-2 (they move pixels
/// app-wide and are explicitly out of scope for pass-1).
///
/// Pure constants + `const` table, so the whole layer is unit-testable without
/// pumping a widget.
library;

import 'package:flutter/widgets.dart';

/// A single UI/mono type role: a font size + weight + family, mapped to the
/// dominant current value so adoption is pixel-identical (D1).
@immutable
class TypeRole {
  const TypeRole(this.size, this.weight, this.family);

  final double size;
  final FontWeight weight;
  final String family;

  static const String fontUi = 'IBM Plex Sans';
  static const String fontMono = 'JetBrains Mono';
}

/// The documented TYPE SCALE: ~7 UI roles + 2 mono roles, each pinned to the
/// CURRENT dominant value (pass-1 pixel-stable). Accessors on `context` (see
/// `context_ext.dart`, e.g. `context.textBody`) feed off this table and produce
/// the exact same `TextStyle` the old raw `context.ui(size: …)` call did.
abstract final class AppType {
  /// Large section/dialog title — ui 16 / w600 (e.g. dialog titles).
  static const titleLg = TypeRole(16, FontWeight.w600, TypeRole.fontUi);

  /// Title — ui 14 / w600 (group headers, prominent labels).
  static const title = TypeRole(14, FontWeight.w600, TypeRole.fontUi);

  /// Body / default button text — ui 13 / w400 (the dominant body size).
  static const body = TypeRole(13, FontWeight.w400, TypeRole.fontUi);

  /// Field/inline label — ui 12.5 / w500.
  static const label = TypeRole(12.5, FontWeight.w500, TypeRole.fontUi);

  /// Caption / helper text — ui 11.5 / w400.
  static const caption = TypeRole(11.5, FontWeight.w400, TypeRole.fontUi);

  /// Overline / smallest meta — ui 11 / w500.
  static const overline = TypeRole(11, FontWeight.w500, TypeRole.fontUi);

  /// Monospace body — mono 13 / w400 (terminal-adjacent body text).
  static const monoBody = TypeRole(13, FontWeight.w400, TypeRole.fontMono);

  /// Monospace caption — mono 11.5 / w400.
  static const monoCaption = TypeRole(11.5, FontWeight.w400, TypeRole.fontMono);

  /// All roles, for table-driven tests.
  static const all = <TypeRole>[
    titleLg,
    title,
    body,
    label,
    caption,
    overline,
    monoBody,
    monoCaption,
  ];
}

/// SPACING scale on a 4pt grid (one half-step `xxs2` is allowed for hairline
/// gaps). Named tokens so call-sites stop hand-writing `8` / `12` / `16`.
abstract final class Spacing {
  /// 2pt — half-step hairline gap (the only off-4pt token, intentionally).
  static const double xxs2 = 2;

  /// 4pt.
  static const double xs4 = 4;

  /// 8pt.
  static const double sm8 = 8;

  /// 12pt.
  static const double md12 = 12;

  /// 16pt.
  static const double lg16 = 16;

  /// 24pt.
  static const double xl24 = 24;

  /// 32pt.
  static const double xxl32 = 32;

  /// All spacing tokens, for grid-validation tests.
  static const values = <double>[xxs2, xs4, sm8, md12, lg16, xl24, xxl32];
}

/// A token-driven [SizedBox] gap. `Gap(Spacing.sm8)` is an 8px square gap; pass
/// [horizontal] to lay it out only on the cross axis is unnecessary — use the
/// named axis helpers when direction matters.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key}) : _axis = null;

  /// A gap that only takes width (use inside a [Row]).
  const Gap.h(this.size, {super.key}) : _axis = Axis.horizontal;

  /// A gap that only takes height (use inside a [Column]).
  const Gap.v(this.size, {super.key}) : _axis = Axis.vertical;

  final double size;
  final Axis? _axis;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _axis == Axis.vertical ? null : size,
    height: _axis == Axis.horizontal ? null : size,
  );
}

/// `EdgeInsets` helpers built from [Spacing] tokens, so padding is expressed in
/// the scale rather than raw literals.
abstract final class Insets {
  static EdgeInsets all(double v) => EdgeInsets.all(v);

  static EdgeInsets symmetric({double h = 0, double v = 0}) =>
      EdgeInsets.symmetric(horizontal: h, vertical: v);

  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) => EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);
}

/// ICON-SIZE ramp (D1c). The shared primitives draw from these named sizes;
/// the inline `14` is a smaller off-ramp glyph kept for dense chips.
abstract final class IconSizes {
  /// 14 — small inline glyph (off-ramp; dense chips/ghosts).
  static const double inline14 = 14;

  /// 16 — default control icon (buttons, icon-buttons).
  static const double sm16 = 16;

  /// 20 — navigation/medium icon (rail).
  static const double md20 = 20;

  /// 24 — large icon.
  static const double lg24 = 24;
}

/// RADIUS scale (D1d). `md8` is the dominant control radius already in use.
abstract final class Radii {
  /// 4 — small (chips, hairlines).
  static const double sm4 = 4;

  /// 8 — default control radius (buttons, fields, icon-buttons).
  static const double md8 = 8;

  /// 12 — large (the toggle track, cards).
  static const double lg12 = 12;

  /// Fully-rounded (pill) radius.
  static const double pill = 999;
}

/// Minimum interactive target size (WCAG 2.5.5 / 2.5.8). The shared [Pressable]
/// enlarges the HIT AREA (not the painted size) to at least this, so a control
/// can paint smaller while still being an easy, accessible target.
const double kMinTapTarget = 44;
