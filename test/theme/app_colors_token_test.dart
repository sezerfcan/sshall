import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  test('all three themes define amber, distinct from green/red/yellow', () {
    for (final c in const [
      AppColors.night,
      AppColors.day,
      AppColors.terminal,
    ]) {
      expect(c.amber, isNot(c.green));
      expect(c.amber, isNot(c.red));
      // amber is its own warning/in-progress token, separate from the legacy
      // generic `yellow` accent.
      expect(c.amber, isNot(c.textDim));
    }
  });

  test('lerp(0.5) produces an intermediate amber', () {
    final mid = AppColors.night.lerp(AppColors.day, 0.5);
    final expected = Color.lerp(
      AppColors.night.amber,
      AppColors.day.amber,
      0.5,
    );
    expect(mid.amber, expected);
  });

  test('copyWith preserves and overrides amber', () {
    const override = Color(0xFF123456);
    expect(AppColors.night.copyWith().amber, AppColors.night.amber);
    expect(AppColors.night.copyWith(amber: override).amber, override);
  });
}
