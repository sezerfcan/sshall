import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/nav_rail.dart';
import 'package:sshall/features/shell/shell_metrics.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: NavRail()),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets(
    'sidebar toggle flips sidebarVisibleProvider (and tooltip) (§9)',
    (tester) async {
      final container = await pump(tester);

      // The binding glyph is platform-aware (⌘B on macOS, Ctrl+B elsewhere),
      // matching how the destination-item tooltips assert their shortcuts.
      final glyph = primaryModifierGlyph();
      final binding = glyph == '⌘' ? '${glyph}B' : '$glyph+B';

      // Default: sidebar visible, toggle present and discoverable.
      expect(container.read(sidebarVisibleProvider), isTrue);
      final toggle = find.byKey(const Key('sidebarToggle'));
      expect(toggle, findsOneWidget);
      expect(find.byTooltip('Kenar çubuğunu gizle ($binding)'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();

      expect(container.read(sidebarVisibleProvider), isFalse);
      // Tooltip reflects the new (hidden) state.
      expect(find.byTooltip('Kenar çubuğunu göster ($binding)'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();
      expect(container.read(sidebarVisibleProvider), isTrue);
    },
  );

  testWidgets('Vault & Settings items toggle the overlay (ADR 0022)', (
    tester,
  ) async {
    final container = await pump(tester);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);

    await tester.tap(find.byKey(const Key('navVault')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.vault);

    // Selecting Settings replaces the Vault overlay (one at a time).
    await tester.tap(find.byKey(const Key('navSettings')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.settings);

    // Tapping the active overlay item again closes it.
    await tester.tap(find.byKey(const Key('navSettings')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
  });

  testWidgets('Connections item requests the home surface', (tester) async {
    final container = await pump(tester);
    container.read(homeRequestedProvider.notifier).state = false;
    container.read(activeOverlayProvider.notifier).state =
        ShellOverlay.settings;

    await tester.tap(find.byKey(const Key('navConnections')));
    await tester.pump();
    expect(container.read(homeRequestedProvider), isTrue);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
  });
}
