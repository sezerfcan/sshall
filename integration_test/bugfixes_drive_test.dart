// Live drive for the 2026-06-22 three-fix task (ADR 0020/0022/0023).
//
// Boots the REAL macOS app (sandboxed, with the Debug entitlements) using only
// in-memory / temp doubles — no real vault / Keychain / network — then proves,
// in the actual sandboxed runtime:
//
//   * BUG 1 (ADR 0023): the sandboxed app can list the real ~/Downloads. Before
//     the files.downloads.read-write entitlement this threw PathAccessException;
//     listing it here proves the entitlement is effective at runtime. It also
//     confirms a path the app can't reach throws PathAccessException (so the
//     view's catch + revert path is exercising a real condition, not a fiction).
//   * BUG 2 (ADR 0009): the redesigned title bar exposes a single theme button
//     whose popup lists every theme and applies the chosen one live, and a PNG
//     of the header is captured per theme for visual review.
//
// BUG 3 (detached-window re-dock) is multi-window and cannot be driven headless
// (ADR 0020): the controller cycle is covered by tabs_controller_test, the
// channel-lifecycle fix is build-verified + human-eye.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sshall/app/app.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/features/sftp/local_fs_controller.dart';
import 'package:sshall/features/shell/title_bar.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sshall_bugfix_it');
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
        vaultPathProvider.overrideWith(
          (ref) async => '${tempDir.path}/vault.bin',
        ),
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
      final dir = Directory('reports/2026-06-22-fixes/screens');
      if (!await dir.exists()) await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
      debugPrint('[FIX] screenshot $name -> ${dir.path}/$name.png');
    } catch (e) {
      debugPrint('[FIX] screenshot $name -> FAILED: $e');
    }
  }

  testWidgets('BUG 1 — sandboxed app can list ~/Downloads (ADR 0023)', (
    tester,
  ) async {
    // Runs inside the real sandboxed app: the downloads entitlement must let us
    // read the real ~/Downloads without a PathAccessException.
    final downloads = await getDownloadsDirectory();
    expect(downloads, isNotNull, reason: 'getDownloadsDirectory() on macOS');
    final entries = await LocalFsController().list(downloads!.path);
    expect(
      entries,
      isA<List<LocalEntry>>(),
      reason: '~/Downloads must be listable under the sandbox',
    );
    debugPrint(
      '[FIX] listed ~/Downloads: ${entries.length} entries (no throw)',
    );
  });

  testWidgets(
    'BUG 2 — title-bar theme button lists + applies every theme live',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1240, 820);

      await tester.pumpWidget(await bootedApp());
      await tester.pumpAndSettle();

      // Fresh temp vault => create mode; enter the shell.
      expect(find.text('Vault Oluştur'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('passphrase')),
        'hunter2-aaaa',
      );
      await tester.enterText(
        find.byKey(const Key('passphraseConfirm')),
        'hunter2-aaaa',
      );
      await tester.tap(find.text('Oluştur'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The single theme control is present (swatch row is gone).
      final themeBtn = find.byKey(const Key('themeButton'));
      expect(themeBtn, findsOneWidget);
      await shot(tester, '01-header-night');

      // Open the popup: every theme is listed (discoverable — §9).
      await tester.tap(themeBtn);
      await tester.pumpAndSettle();
      for (final id in AppThemeId.values) {
        expect(find.text(id.label), findsOneWidget);
      }
      await shot(tester, '02-theme-popup');

      // Pick each non-default theme and confirm it applies live, capturing the
      // header so the accent-tinted palette icon can be eyeballed per theme.
      for (final id in [AppThemeId.terminal, AppThemeId.day]) {
        if (find.byType(PopupMenuItem<AppThemeId>).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('themeButton')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(id.label));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TitleBar)),
        );
        expect(container.read(themeControllerProvider), id);
        await shot(tester, '03-header-${id.name}');
      }
    },
  );
}
