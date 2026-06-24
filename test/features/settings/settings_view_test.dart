import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/settings/app_settings.dart';
import 'package:sshall/features/settings/settings_row.dart';
import 'package:sshall/features/settings/settings_view.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  double width = 1000,
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(sp)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appThemeData(AppThemeId.night),
        home: const Scaffold(body: SettingsView()),
      ),
    ),
  );
  await tester.pump();
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

  group('master/detail nav (D1)', () {
    testWidgets('the nav lists every group + a separated danger zone', (
      tester,
    ) async {
      await _pump(tester);
      for (final g in SettingsGroup.values) {
        expect(find.byKey(Key('settingsNav_${g.label}')), findsOneWidget);
      }
      expect(
        find.byKey(const Key('settingsNav_Tehlikeli Bölge')),
        findsOneWidget,
      );
    });

    testWidgets('selecting a nav item switches the detail pane', (
      tester,
    ) async {
      await _pump(tester);
      // Appearance is selected by default → theme cards visible.
      expect(find.byKey(const Key('themeCard_night')), findsOneWidget);

      // Switch to Terminal → its rows appear, the theme cards are gone.
      await tester.tap(find.byKey(const Key('settingsNav_Terminal')));
      await tester.pumpAndSettle();
      expect(find.text('Yazı boyutu'), findsOneWidget);
      expect(find.byKey(const Key('themeCard_night')), findsNothing);
    });

    testWidgets('narrow width collapses the nav into a dropdown', (
      tester,
    ) async {
      await _pump(tester, width: 520);
      expect(find.byKey(const Key('settingsNavDropdown')), findsOneWidget);
      // The wide rail items are not laid out as a column anymore.
      expect(find.byKey(const Key('settingsNav_Terminal')), findsNothing);
    });
  });

  group('in-page search (D2)', () {
    testWidgets('search filters rows live', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('settingsSearch')), 'port');
      await tester.pumpAndSettle();
      expect(find.text('Varsayılan port'), findsOneWidget);
      // A terminal row that does not match is hidden.
      expect(find.text('Yazı boyutu'), findsNothing);
    });

    testWidgets('selecting a search result jumps to its group', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('settingsSearch')), 'port');
      await tester.pumpAndSettle();
      // Tap the group header in the results → jumps to Connection, clears search.
      await tester.tap(find.byKey(const Key('searchGroup_connection')));
      await tester.pumpAndSettle();
      // Search cleared → the Connection section header shows.
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('settingsSearch')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, isEmpty);
      expect(find.text('Varsayılan port'), findsOneWidget);
    });

    testWidgets('an empty result shows the no-results hint', (tester) async {
      await _pump(tester);
      await tester.enterText(
        find.byKey(const Key('settingsSearch')),
        'zzz-no-such',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settingsNoResults')), findsOneWidget);
    });
  });

  group('appearance / theme cards (D4)', () {
    testWidgets('theme cards show full canonical labels (no clip)', (
      tester,
    ) async {
      await _pump(tester);
      // The full AppThemeIdLabel.label strings are shown, not a local literal.
      expect(find.text('Gece (Tokyo Night)'), findsOneWidget);
      expect(find.text('Gündüz (Açık)'), findsOneWidget);
      expect(find.text('Terminal (Yeşil)'), findsOneWidget);
    });

    testWidgets(
      'the active card has a strong selected state + tapping switches',
      (tester) async {
        final container = await _pump(tester);
        expect(container.read(themeControllerProvider), AppThemeId.night);
        // Active (night) card carries the check mark; tap terminal to switch.
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        await tester.tap(find.byKey(const Key('themeCard_terminal')));
        await tester.pumpAndSettle();
        expect(container.read(themeControllerProvider), AppThemeId.terminal);
      },
    );

    testWidgets('each theme card carries a full-name tooltip', (tester) async {
      await _pump(tester);
      expect(find.byTooltip('Gece (Tokyo Night)'), findsOneWidget);
    });
  });

  group('terminal settings (D5)', () {
    testWidgets('the font-size stepper writes the global default', (
      tester,
    ) async {
      final container = await _pump(tester);
      await tester.tap(find.byKey(const Key('settingsNav_Terminal')));
      await tester.pumpAndSettle();
      // Increment the font size.
      final before = container
          .read(appSettingsControllerProvider)
          .terminalFontSize;
      await tester.tap(find.byKey(const Key('stepperInc')).first);
      await tester.pump();
      expect(
        container.read(appSettingsControllerProvider).terminalFontSize,
        before + 1,
      );
    });
  });

  group('connection settings (D6)', () {
    testWidgets('the port field persists a typed default port', (tester) async {
      final container = await _pump(tester, prefs: {'defaultPort': 2000});
      await tester.tap(find.byKey(const Key('settingsNav_Bağlantı')));
      await tester.pumpAndSettle();
      // Type a non-22 port directly — a single set, not 2000 stepper clicks.
      await tester.enterText(
        find.byKey(const Key('defaultPortField')),
        '2222',
      );
      await tester.pump();
      expect(container.read(appSettingsControllerProvider).defaultPort, 2222);
    });

    testWidgets('the port field is digits-only and clearing falls back to 22', (
      tester,
    ) async {
      final container = await _pump(tester, prefs: {'defaultPort': 2222});
      await tester.tap(find.byKey(const Key('settingsNav_Bağlantı')));
      await tester.pumpAndSettle();
      // Non-digits are filtered out by the input formatter.
      await tester.enterText(
        find.byKey(const Key('defaultPortField')),
        '2a2b',
      );
      await tester.pump();
      expect(container.read(appSettingsControllerProvider).defaultPort, 22);
      // Clearing the field falls back to the canonical default (22).
      await tester.enterText(find.byKey(const Key('defaultPortField')), '');
      await tester.pump();
      expect(container.read(appSettingsControllerProvider).defaultPort, 22);
    });

    testWidgets(
      'the username field re-syncs when the stored value changes while open',
      (tester) async {
        final container = await _pump(
          tester,
          prefs: {'defaultUsername': 'olduser'},
        );
        await tester.tap(find.byKey(const Key('settingsNav_Bağlantı')));
        await tester.pumpAndSettle();
        String fieldText() => tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('defaultUsernameField')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text;
        expect(fieldText(), 'olduser');
        // An external store mutation (e.g. reset path) while the field is
        // mounted must propagate to the controller via didUpdateWidget.
        container
            .read(appSettingsControllerProvider.notifier)
            .setDefaultUsername('');
        await tester.pump();
        expect(fieldText(), isEmpty);
      },
    );
  });

  group('behavior settings (D7)', () {
    testWidgets('the confirm-on-close toggle persists', (tester) async {
      final container = await _pump(tester);
      await tester.tap(find.byKey(const Key('settingsNav_Davranış')));
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingsControllerProvider).confirmOnCloseLiveSession,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('confirmOnCloseToggle')));
      await tester.pump();
      expect(
        container.read(appSettingsControllerProvider).confirmOnCloseLiveSession,
        isFalse,
      );
    });
  });

  group('keyboard shortcuts (D8)', () {
    testWidgets('the shortcuts list renders bindings + descriptions', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('settingsNav_Klavye Kısayolları')));
      await tester.pumpAndSettle();
      // A known binding + its description from the shared source.
      expect(find.text('Aktif oturum sekmesini kapat'), findsOneWidget);
      expect(find.text('⌘W'), findsWidgets);
    });
  });

  group('about (D9)', () {
    testWidgets('the About card shows the runtime version + clickable links', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('settingsNav_Hakkında')));
      await tester.pumpAndSettle();
      expect(find.text('sshall 1.0.0 (build 1)'), findsOneWidget);
      // Links are tappable widgets, not plain Text.
      expect(find.byKey(const Key('aboutLinkRepo')), findsOneWidget);
      expect(find.byKey(const Key('aboutLinkLicense')), findsOneWidget);
      expect(find.byKey(const Key('aboutLinkChangelog')), findsOneWidget);
    });
  });

  group('danger zone (D10)', () {
    testWidgets(
      'both reset-settings (lesser) and reset-vault (strongest) exist',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.byKey(const Key('settingsNav_Tehlikeli Bölge')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settingsResetSettings')), findsOneWidget);
        expect(find.byKey(const Key('settingsResetVault')), findsOneWidget);
      },
    );

    testWidgets('reset-settings clears AppSettings (vault untouched)', (
      tester,
    ) async {
      final container = await _pump(tester);
      container
          .read(appSettingsControllerProvider.notifier)
          .setTerminalFontSize(20);
      await tester.tap(find.byKey(const Key('settingsNav_Tehlikeli Bölge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settingsResetSettings')));
      await tester.pumpAndSettle();
      // Confirm in the dialog.
      await tester.tap(find.byKey(const Key('confirmResetSettings')));
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingsControllerProvider).terminalFontSize,
        13,
      );
    });

    testWidgets(
      'reset-settings clears the username field while Settings stays open',
      (tester) async {
        final container = await _pump(
          tester,
          prefs: {'defaultUsername': 'admin'},
        );
        // Open the Connection group so the username field is mounted.
        await tester.tap(find.byKey(const Key('settingsNav_Bağlantı')));
        await tester.pumpAndSettle();
        String fieldText() => tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('defaultUsernameField')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text;
        expect(fieldText(), 'admin');
        // Reset the settings store directly (the danger-zone button path) while
        // the field is still on screen — the field must drop the stale 'admin'.
        container.read(appSettingsControllerProvider.notifier).reset();
        await tester.pump();
        expect(fieldText(), isEmpty);
      },
    );

    testWidgets('the reset-vault type-SIFIRLA confirm is preserved', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('settingsNav_Tehlikeli Bölge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settingsResetVault')));
      await tester.pumpAndSettle();
      // The type-SIFIRLA confirm dialog appears, with its confirm gated.
      expect(find.byKey(const Key('resetConfirmPhrase')), findsOneWidget);
      expect(find.byKey(const Key('confirmReset')), findsOneWidget);
    });
  });
}
