import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/settings/settings_view.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

/// Golden coverage for the sectioned settings surface (ADR 0038):
///   1. the master/detail nav + a settings group (Terminal: stepper + dropdown),
///   2. the Appearance theme cards (canonical labels + the selected state),
///   3. the danger zone (reset-settings amber vs reset-vault red, separated),
/// in all three themes (night / day / terminal). Regenerate with:
///   flutter test --update-goldens test/features/settings/settings_golden_test.dart
/// then run without the flag to confirm they pass.

const _themes = AppThemeId.values;

Future<ProviderContainer> _pump(
  WidgetTester tester,
  AppThemeId theme, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appThemeData(theme),
        home: const Scaffold(body: SettingsView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'sshall',
      packageName: 'com.sshall.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  for (final theme in _themes) {
    testWidgets('sectioned settings — Appearance — ${theme.name}', (
      tester,
    ) async {
      await _pump(tester, theme, size: const Size(820, 560));
      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_appearance_${theme.name}.png'),
      );
    });

    testWidgets('sectioned settings — Terminal group — ${theme.name}', (
      tester,
    ) async {
      await _pump(tester, theme, size: const Size(820, 560));
      await tester.tap(find.byKey(const Key('settingsNav_Terminal')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_terminal_${theme.name}.png'),
      );
    });

    testWidgets('danger zone — reset-settings vs reset-vault — ${theme.name}', (
      tester,
    ) async {
      await _pump(tester, theme, size: const Size(820, 560));
      await tester.tap(find.byKey(const Key('settingsNav_Tehlikeli Bölge')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_danger_${theme.name}.png'),
      );
    });
  }
}
