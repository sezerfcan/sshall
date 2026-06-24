import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'tokens.dart';

extension AppColorsContext on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;

  TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.text,
    height: 1.5,
  );

  TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: 'IBM Plex Sans',
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.text,
    letterSpacing: spacing,
  );
}

/// Named TYPE SCALE role accessors (ADR 0040 D1). Each role is pinned to the
/// CURRENT dominant value (see `tokens.dart`), so swapping a raw
/// `context.ui(size: 13)` for `context.textBody` is PIXEL-IDENTICAL. Authors
/// should reach for these named roles instead of hand-typing a font size.
///
/// The raw `context.ui({size})` / `context.mono({size})` API above is preserved
/// for call-sites the pass-1 migration intentionally leaves untouched (pass-2
/// consolidates them onto these roles).
extension AppTypeRoles on BuildContext {
  TextStyle _role(TypeRole r, {Color? color, double spacing = 0}) =>
      r.family == TypeRole.fontMono
      ? mono(size: r.size, weight: r.weight, color: color)
      : ui(size: r.size, weight: r.weight, color: color, spacing: spacing);

  /// ui 16 / w600 — large dialog/section title.
  TextStyle textTitleLg({Color? color}) => _role(AppType.titleLg, color: color);

  /// ui 14 / w600 — title / group header.
  TextStyle textTitle({Color? color}) => _role(AppType.title, color: color);

  /// ui 13 / w400 — body / default button text.
  TextStyle textBody({Color? color}) => _role(AppType.body, color: color);

  /// ui 12.5 / w500 — field / inline label.
  TextStyle textLabel({Color? color}) => _role(AppType.label, color: color);

  /// ui 11.5 / w400 — caption / helper text.
  TextStyle textCaption({Color? color}) => _role(AppType.caption, color: color);

  /// ui 11 / w500 — overline / smallest meta.
  TextStyle textOverline({Color? color}) =>
      _role(AppType.overline, color: color);

  /// mono 13 / w400 — monospace body.
  TextStyle monoBody({Color? color}) => _role(AppType.monoBody, color: color);

  /// mono 11.5 / w400 — monospace caption.
  TextStyle monoCaption({Color? color}) =>
      _role(AppType.monoCaption, color: color);
}
