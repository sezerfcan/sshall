import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  test('defaults to night and persists selection', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(themeControllerProvider), AppThemeId.night);
    c.read(themeControllerProvider.notifier).set(AppThemeId.terminal);
    expect(c.read(themeControllerProvider), AppThemeId.terminal);
    expect(prefs.getString('themeId'), 'terminal');
  });

  test('reads persisted selection on init', () async {
    SharedPreferences.setMockInitialValues({'themeId': 'day'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(themeControllerProvider), AppThemeId.day);
  });
}
