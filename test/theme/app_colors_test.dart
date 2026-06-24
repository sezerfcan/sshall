import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  test('night palette has the spec accent and bg', () {
    const c = AppColors.night;
    expect(c.bg, const Color(0xFF16161E));
    expect(c.accent, const Color(0xFF7AA2F7));
    expect(c.green, const Color(0xFF9ECE6A));
  });

  test('of() maps ids to palettes', () {
    expect(AppColors.of(AppThemeId.day).accent, const Color(0xFF2E7DE9));
    expect(AppColors.of(AppThemeId.terminal).accent, const Color(0xFF3FB950));
  });

  test('lerp interpolates between palettes', () {
    final mid = AppColors.night.lerp(AppColors.day, 1.0);
    expect(mid.accent, AppColors.day.accent);
  });
}
