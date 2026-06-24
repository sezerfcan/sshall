import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/title_bar.dart';
import 'package:sshall/features/shell/window_chrome.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

/// Golden coverage for the unified title + toolbar (ADR 0039):
///   1. the WIDE bar with an active-session title centered between the brand and
///      the full trailing cluster [Klavye kısayolları] [Tema] [Ayarlar], and
///   2. the NARROW / overflow state — the centered title dropped and the
///      trailing cluster collapsed into the "⋯" superset (icon-only wordmark),
/// in all three themes (night / day / terminal). Regenerate with:
///   flutter test --update-goldens test/features/shell/title_bar_golden_test.dart
/// then run without the flag to confirm they pass.

const _themes = AppThemeId.values;

/// A no-op chrome seam so the bar pumps without driving window_manager.
class _NoopChrome implements WindowChrome {
  const _NoopChrome();
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  Future<void> setTitle(String title) async {}
  @override
  Future<bool> isFullScreen() async => false;
}

Future<void> _pumpBar(
  WidgetTester tester,
  AppThemeId theme, {
  required double width,
  required String? title,
}) async {
  tester.view.physicalSize = Size(width, 42);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      windowChromeProvider.overrideWithValue(const _NoopChrome()),
      activeSessionTitleProvider.overrideWithValue(title),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appThemeData(theme),
        home: SizedBox(
          width: width,
          child: const Scaffold(body: TitleBar()),
        ),
      ),
    ),
  );
  // Resolve the runtime-version FutureBuilder so the badge is rendered.
  await tester.pumpAndSettle();
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
    testWidgets('title bar — active title + full cluster — ${theme.name}', (
      tester,
    ) async {
      await _pumpBar(tester, theme, width: 1200, title: 'web.example.com');
      await expectLater(
        find.byType(TitleBar),
        matchesGoldenFile('goldens/title_bar_wide_${theme.name}.png'),
      );
    });

    testWidgets('title bar — narrow / overflow — ${theme.name}', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        theme,
        width: 720, // < titleOverflow → whole cluster in ⋯, title dropped
        title: 'web.example.com',
      );
      await expectLater(
        find.byType(TitleBar),
        matchesGoldenFile('goldens/title_bar_narrow_${theme.name}.png'),
      );
    });
  }
}
