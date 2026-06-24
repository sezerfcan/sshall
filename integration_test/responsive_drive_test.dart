// Live responsive-chrome drive (ADR 0021).
//
// Boots the REAL app on macOS, unlocks into the AppShell, then resizes the
// Flutter view to several widths and asserts the adaptive title bar + sidebar
// behave as designed, writing a PNG at each stage as visual evidence. Uses only
// in-memory / temp doubles (no real vault / Keychain / network), mirroring
// app_drive_test.dart.
//
// What it proves live (real macOS engine, real fonts):
//   * wide  -> version label + inline theme chips + help button, sidebar shown
//   * medium-> version label hidden, chips still inline
//   * narrow-> toolbar collapsed into the "⋯" overflow menu
//   * sidebar toggle hides/shows the connection sidebar
//
// Tab pill icon-only / title-shrink is covered by widget tests (tab_pill_test,
// shell_tab_bar_test) which render the same code at controlled panel widths.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sshall/app/app.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/features/shell/connection_sidebar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final boundaryKey = GlobalKey();
  var shots = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sshall_resp_it');
  });
  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<Widget> bootedApp() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        keyringProvider.overrideWithValue(InMemoryKeyring()),
        vaultPathProvider.overrideWith((ref) async => '${tempDir.path}/vault.bin'),
      ],
      child: RepaintBoundary(key: boundaryKey, child: const SshallApp()),
    );
  }

  Future<void> shot(WidgetTester tester, String name) async {
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = Directory('reports/adr-0021/screens');
      if (!await dir.exists()) await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
      shots++;
      debugPrint('[RESP] screenshot $name -> ${dir.path}/$name.png');
    } catch (e) {
      debugPrint('[RESP] screenshot $name -> FAILED: $e');
    }
  }

  Future<void> setSize(WidgetTester tester, double w, double h) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(w, h);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }

  testWidgets('adaptive title bar + sidebar (ADR 0021)', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await bootedApp());
    await tester.pumpAndSettle();

    // Unlock: fresh temp vault => create mode. Make the vault and enter the shell.
    expect(find.text('Vault Oluştur'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('passphrase')),
      'hunter2-correct',
    );
    await tester.enterText(
      find.byKey(const Key('passphraseConfirm')),
      'hunter2-correct',
    );
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- wide: everything inline, sidebar visible ---
    await setSize(tester, 1240, 820);
    expect(find.text('v0.3.0 · MVP'), findsOneWidget);
    expect(find.byKey(const Key('shortcutsHelpButton')), findsOneWidget);
    expect(find.byKey(const Key('titleOverflowButton')), findsNothing);
    expect(find.byType(ConnectionSidebar), findsOneWidget);
    await shot(tester, '01-wide');

    // --- medium: version hidden, chips still inline ---
    await setSize(tester, 860, 760);
    expect(find.text('v0.3.0 · MVP'), findsNothing);
    expect(find.byKey(const Key('titleOverflowButton')), findsNothing);
    expect(find.byKey(const Key('shortcutsHelpButton')), findsOneWidget);
    await shot(tester, '02-medium');

    // --- narrow: toolbar collapsed into ⋯ overflow ---
    await setSize(tester, 720, 720);
    expect(find.byKey(const Key('titleOverflowButton')), findsOneWidget);
    expect(find.byKey(const Key('shortcutsHelpButton')), findsNothing);
    await shot(tester, '03-narrow-overflow');

    // --- sidebar toggle hides the connection sidebar ---
    await setSize(tester, 980, 760);
    expect(find.byType(ConnectionSidebar), findsOneWidget);
    await tester.tap(find.byKey(const Key('sidebarToggle')));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionSidebar), findsNothing);
    await shot(tester, '04-sidebar-hidden');
    // Toggle back so the shell is left in its default state.
    await tester.tap(find.byKey(const Key('sidebarToggle')));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionSidebar), findsOneWidget);

    debugPrint('[RESP] done — $shots screenshots written');
  });
}
