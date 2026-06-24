import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/shell/nav_rail.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

/// Behavior coverage for the rail-as-mode-switcher (ADR 0030 D2/D7).
void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
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
          theme: appThemeData(AppThemeId.night),
          home: const Scaffold(body: NavRail()),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets(
    'clicking the ALREADY-active Connections item toggles the panel (D2)',
    (tester) async {
      final container = await pump(tester);
      // No sessions + overlay none → Connections is the active place; panel
      // starts visible.
      expect(container.read(sidebarVisibleProvider), isTrue);

      await tester.tap(find.byKey(const Key('navConnections')));
      await tester.pump();
      // Re-tapping the active place collapses the panel.
      expect(container.read(sidebarVisibleProvider), isFalse);

      await tester.tap(find.byKey(const Key('navConnections')));
      await tester.pump();
      // ...and toggles it back open.
      expect(container.read(sidebarVisibleProvider), isTrue);
    },
  );

  testWidgets(
    'clicking a DIFFERENT place ensures the panel is visible + switches (D2)',
    (tester) async {
      final container = await pump(tester);
      // Open the Settings overlay and collapse the panel first.
      container.read(activeOverlayProvider.notifier).state =
          ShellOverlay.settings;
      container.read(sidebarControllerProvider.notifier).setCollapsed(true);
      await tester.pump();
      expect(container.read(sidebarVisibleProvider), isFalse);

      // Connections is NOT active now (overlay = settings) → switching to it
      // closes the overlay, requests home AND ensures the panel is visible.
      await tester.tap(find.byKey(const Key('navConnections')));
      await tester.pump();
      expect(container.read(activeOverlayProvider), ShellOverlay.none);
      expect(container.read(homeRequestedProvider), isTrue);
      expect(container.read(sidebarVisibleProvider), isTrue);
    },
  );

  testWidgets('rail tooltips name the destination AND its shortcut (D7)', (
    tester,
  ) async {
    // Pin the platform so the glyph is deterministic regardless of CI host.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pump(tester);
      // Each rail destination's tooltip carries its ⌘1..4 shortcut (§9).
      expect(find.byTooltip('Bağlantılar  ⌘1'), findsOneWidget);
      expect(find.byTooltip('SFTP  ⌘2'), findsOneWidget);
      expect(find.byTooltip('Vault  ⌘3'), findsOneWidget);
      expect(find.byTooltip('Ayarlar  ⌘4'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Vault / Settings remain overlay toggles (D2)', (tester) async {
    final container = await pump(tester);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);

    await tester.tap(find.byKey(const Key('navVault')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.vault);

    // Tapping the active Vault item again closes it.
    await tester.tap(find.byKey(const Key('navVault')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
  });
}
