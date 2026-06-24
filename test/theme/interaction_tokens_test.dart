import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';

/// Relative luminance of an opaque color (WCAG 2.x formula).
double _luminance(Color color) {
  double channel(double c) {
    final s = c; // already 0..1 in the modern Color API
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG contrast ratio between two opaque colors (1..21).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const themes = <String, AppColors>{
    'night': AppColors.night,
    'day': AppColors.day,
    'terminal': AppColors.terminal,
  };

  test('all six interaction tokens are defined in every theme', () {
    for (final c in themes.values) {
      // ignore: unnecessary_null_comparison
      expect(c.hoverOverlay, isNotNull);
      expect(c.pressedOverlay, isNotNull);
      expect(c.focusRing, isNotNull);
      expect(c.selectedBg, isNotNull);
      expect(c.disabledFg, isNotNull);
      expect(c.onAccent, isNotNull);
    }
  });

  test('selectedBg is an alias of accentSoft (pixel-identical selection)', () {
    for (final entry in themes.entries) {
      expect(
        entry.value.selectedBg,
        entry.value.accentSoft,
        reason: '${entry.key}: selectedBg must equal accentSoft',
      );
    }
  });

  test(
    'focusRing has >=3:1 contrast against surface and surface2 (incl. day)',
    () {
      for (final entry in themes.entries) {
        final c = entry.value;
        expect(
          _contrast(c.focusRing, c.surface),
          greaterThanOrEqualTo(3.0),
          reason: '${entry.key}: focusRing vs surface',
        );
        expect(
          _contrast(c.focusRing, c.surface2),
          greaterThanOrEqualTo(3.0),
          reason: '${entry.key}: focusRing vs surface2',
        );
      }
    },
  );

  test('pressedOverlay is more intense than hoverOverlay', () {
    for (final entry in themes.entries) {
      final c = entry.value;
      // Same accent hue, stronger alpha => higher opacity for pressed.
      expect(
        c.pressedOverlay.a,
        greaterThan(c.hoverOverlay.a),
        reason: '${entry.key}: pressed must be stronger than hover',
      );
    }
  });

  test('onAccent is the high-contrast white knob mark (pixel-stable)', () {
    // The knob is a decorative thumb on the accent track (not a text/UI
    // component, so WCAG 2.4.11 3:1 does not apply); it must stay the existing
    // white so the toggle golden is unchanged.
    for (final entry in themes.entries) {
      expect(
        entry.value.onAccent,
        const Color(0xFFFFFFFF),
        reason: '${entry.key}: onAccent must remain the white knob mark',
      );
      // Still a clearly luminous mark against the surrounding surface.
      expect(_luminance(entry.value.onAccent), greaterThan(0.8));
    }
  });

  test('copyWith overrides and lerp carries the new fields', () {
    const x = Color(0xFF112233);
    expect(AppColors.night.copyWith(focusRing: x).focusRing, x);
    expect(
      AppColors.night.copyWith().hoverOverlay,
      AppColors.night.hoverOverlay,
    );

    final mid = AppColors.night.lerp(AppColors.day, 0.5);
    expect(
      mid.focusRing,
      Color.lerp(AppColors.night.focusRing, AppColors.day.focusRing, 0.5),
    );
    expect(
      mid.selectedBg,
      Color.lerp(AppColors.night.selectedBg, AppColors.day.selectedBg, 0.5),
    );
  });
}
