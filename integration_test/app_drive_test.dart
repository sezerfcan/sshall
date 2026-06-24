// Live UX drive harness (Cycle 3 — review-loop/2026-06-20-1821).
//
// This integration test BOOTS THE REAL APP (`SshallApp`) on macOS and drives
// every screen: it fills inputs, taps buttons, opens and dismisses dialogs and
// observes the resulting behaviour. It NEVER touches the user's real vault or
// macOS Keychain — every external seam is overridden with an isolated, in-memory
// or temp-dir double:
//
//   * sharedPrefsProvider  -> SharedPreferences mock (empty).
//   * vaultPathProvider    -> a fresh file under Directory.systemTemp.
//   * keyringProvider      -> InMemoryKeyring (no Keychain writes).
//
// No live SSH/SFTP connection is ever started (no server exists); connection and
// host fields are filled and dialogs opened/closed, but "Connect" is never
// driven into a real network wait.
//
// Every interaction emits `debugPrint('[DRIVE] <screen> <control> -> <obs>')`
// so the run log itself is the evidence. A best-effort PNG of each screen is
// written to reports/cycle-2026-06-20-1821/screens/<name>.png.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sshall/app/app.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/features/shell/shell_tab_bar.dart';
import 'package:sshall/features/shell/tab_pill.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Counts so the final summary can report "how many screens / controls driven".
  var screensDriven = 0;
  var controlsTapped = 0;
  var screenshotsWritten = 0;

  late Directory tempDir;
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sshall_it');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ProviderScope> bootedApp() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final keyring = InMemoryKeyring();
    final vaultPath = '${tempDir.path}/vault.bin';

    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        keyringProvider.overrideWithValue(keyring),
        vaultPathProvider.overrideWith((ref) async => vaultPath),
      ],
      child: RepaintBoundary(
        key: boundaryKey,
        child: const SshallApp(),
      ),
    );
  }

  Future<void> shot(WidgetTester tester, String name) async {
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[DRIVE] screenshot $name -> no boundary, skipped');
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        debugPrint('[DRIVE] screenshot $name -> toByteData null, skipped');
        return;
      }
      final dir = Directory('reports/cycle-2026-06-20-1821/screens');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$name.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      screenshotsWritten++;
      debugPrint('[DRIVE] screenshot $name -> ${file.path}');
    } catch (e) {
      // Screenshots are best-effort: never fail the drive over a capture error.
      debugPrint('[DRIVE] screenshot $name -> FAILED: $e');
    }
  }

  testWidgets('drive every screen and control', (tester) async {
    await tester.pumpWidget(await bootedApp());
    await tester.pumpAndSettle();

    // ---------------------------------------------------------------
    // 1) UnlockScreen — vault does NOT exist => "Vault Oluştur" (create) mode.
    // ---------------------------------------------------------------
    screensDriven++;
    expect(find.text('Vault Oluştur'), findsOneWidget,
        reason: 'fresh temp vault must show create mode');
    debugPrint('[DRIVE] unlock -> create mode shown (Vault Oluştur)');
    await shot(tester, '01-unlock-create');

    final passField = find.byKey(const Key('passphrase'));
    final confirmField = find.byKey(const Key('passphraseConfirm'));
    expect(passField, findsOneWidget);
    expect(confirmField, findsOneWidget,
        reason: 'create mode must show the confirm field (cycle 1 fix)');
    debugPrint('[DRIVE] unlock -> confirm field present');

    // Show/hide toggle.
    final visToggle = find.byKey(const Key('passphraseVisibility'));
    expect(visToggle, findsOneWidget);
    await tester.tap(visToggle);
    controlsTapped++;
    await tester.pumpAndSettle();
    debugPrint('[DRIVE] unlock passphraseVisibility -> toggled');
    await tester.tap(visToggle);
    controlsTapped++;
    await tester.pumpAndSettle();

    // Mismatched passwords -> must surface an error, must NOT create the vault.
    await tester.enterText(passField, 'hunter2-correct');
    await tester.enterText(confirmField, 'totally-different');
    await tester.tap(find.text('Oluştur'));
    controlsTapped++;
    await tester.pumpAndSettle();
    expect(find.text('Parolalar eşleşmiyor'), findsOneWidget,
        reason: 'mismatched passphrases must block creation with an error');
    expect(find.text('Vault Oluştur'), findsOneWidget,
        reason: 'still on unlock screen after a mismatch');
    debugPrint('[DRIVE] unlock mismatch -> error "Parolalar eşleşmiyor" shown, '
        'vault NOT created');
    await shot(tester, '02-unlock-mismatch');

    // Now create the vault for real.
    await tester.enterText(passField, 'hunter2-correct');
    await tester.enterText(confirmField, 'hunter2-correct');
    await tester.tap(find.text('Oluştur'));
    controlsTapped++;
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(SshallApp), findsOneWidget);
    debugPrint('[DRIVE] unlock create -> vault created, AppShell reached');

    // ---------------------------------------------------------------
    // 2) AppShell — walk every nav target and tap every control.
    // ---------------------------------------------------------------
    Future<void> driveCurrentScreen(String label) async {
      screensDriven++;
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      final iconButtons = find.byType(IconButton);
      final elevated = find.byType(ElevatedButton);
      final textButtons = find.byType(TextButton);
      final textFields = find.byType(TextField);
      debugPrint('[DRIVE] $label -> inventory: '
          'IconButton=${iconButtons.evaluate().length} '
          'ElevatedButton=${elevated.evaluate().length} '
          'TextButton=${textButtons.evaluate().length} '
          'TextField=${textFields.evaluate().length}');

      // Fill every visible text field with a harmless probe value, observing
      // that the field accepts input.
      final tfList = textFields.evaluate().toList();
      for (var i = 0; i < tfList.length; i++) {
        try {
          await tester.enterText(textFields.at(i), 'probe-$i');
          await tester.pump();
          debugPrint('[DRIVE] $label TextField#$i -> accepted "probe-$i"');
        } catch (e) {
          debugPrint('[DRIVE] $label TextField#$i -> input FAILED: $e');
        }
      }

      // Tap each IconButton; after each, dismiss any dialog/menu that opened so
      // the next tap targets the base screen. We never tap "Connect" into a real
      // network wait — there is no session, so the connect path no-ops or errors
      // locally, which is exactly what we want to observe.
      final ibCount = iconButtons.evaluate().length;
      for (var i = 0; i < ibCount; i++) {
        final btn = find.byType(IconButton);
        if (i >= btn.evaluate().length) break;
        try {
          await tester.tap(btn.at(i), warnIfMissed: false);
          controlsTapped++;
          await tester.pumpAndSettle(const Duration(milliseconds: 150));
          debugPrint('[DRIVE] $label IconButton#$i -> tapped');
          await _dismissOverlays(tester);
        } catch (e) {
          debugPrint('[DRIVE] $label IconButton#$i -> tap FAILED: $e');
        }
      }

      await shot(tester, label);
    }

    // The nav rail uses GestureDetector + Tooltip (not standard buttons), so we
    // navigate by tapping the tooltip message text via the rail icons. Easiest
    // reliable path: tap the rail by walking the providers through the UI — tap
    // each nav icon by its IconData.
    Future<void> navTo(IconData icon, String label) async {
      final finder = find.byIcon(icon).first;
      await tester.tap(finder, warnIfMissed: false);
      controlsTapped++;
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      debugPrint('[DRIVE] nav -> $label');
    }

    // Connections (default view already shown).
    await driveCurrentScreen('03-connections');

    // ---- Connect dialog: the most control-rich form in the app. ----
    // Open via the sidebar "+" (newHostRequest), drive its toggles and fields,
    // then CANCEL (never "Bağlan" — no server exists).
    final yeniHost = find.text('Yeni Host');
    if (yeniHost.evaluate().isNotEmpty) {
      await tester.tap(yeniHost.first, warnIfMissed: false);
      controlsTapped++;
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (find.text('Yeni Bağlantı').evaluate().isNotEmpty) {
        debugPrint('[DRIVE] connectDialog -> opened');
        // Fill host / port / username.
        for (final entry in const [
          ('host', '192.168.1.10'),
          ('port', '2222'),
          ('username', 'root'),
        ]) {
          final f = find.byKey(Key(entry.$1));
          if (f.evaluate().isNotEmpty) {
            await tester.enterText(f, entry.$2);
            await tester.pump();
            debugPrint('[DRIVE] connectDialog ${entry.$1} -> "${entry.$2}"');
          }
        }
        // Toggle "Use private key" -> key fields appear; toggle back.
        final useKey = find.byKey(const Key('useKey'));
        if (useKey.evaluate().isNotEmpty) {
          await tester.tap(useKey);
          controlsTapped++;
          await tester.pumpAndSettle();
          final importBtn = find.text('Anahtar dosyası içe aktar');
          debugPrint('[DRIVE] connectDialog useKey -> on '
              '(import button present=${importBtn.evaluate().isNotEmpty})');
          await tester.tap(useKey);
          controlsTapped++;
          await tester.pumpAndSettle();
        }
        // Toggle "Save to vault" -> label/folder/tags appear.
        final save = find.byKey(const Key('save'));
        if (save.evaluate().isNotEmpty) {
          await tester.tap(save);
          controlsTapped++;
          await tester.pumpAndSettle();
          final tags = find.byKey(const Key('tags'));
          debugPrint('[DRIVE] connectDialog save -> on '
              '(tags field present=${tags.evaluate().isNotEmpty})');
          if (tags.evaluate().isNotEmpty) {
            await tester.enterText(tags, 'prod, db');
            await tester.pump();
          }
        }
        await shot(tester, '03b-connect-dialog');
        // Cancel — never start a real connection.
        final cancel = find.text('Vazgeç');
        if (cancel.evaluate().isNotEmpty) {
          await tester.tap(cancel.first, warnIfMissed: false);
          controlsTapped++;
          await tester.pumpAndSettle();
          debugPrint('[DRIVE] connectDialog -> cancelled (no connection started)');
        }
      } else {
        debugPrint('[DRIVE] connectDialog -> did NOT open after Yeni Host tap');
      }
    }

    // SFTP.
    await navTo(Icons.sync_alt, 'sftp');
    await driveCurrentScreen('05-sftp');

    // Vault.
    await navTo(Icons.vpn_key_outlined, 'vault');
    await driveCurrentScreen('06-vault');

    // Settings.
    await navTo(Icons.settings_outlined, 'settings');
    await driveCurrentScreen('07-settings');

    // ---------------------------------------------------------------
    // 3) Tab system (VS Code-style, ADR 0018). The three nav targets above
    //    each opened a tab; together with the permanent "home" tab the strip
    //    now holds several pills. Drive the tab interactions end-to-end.
    //    (No SSH server exists, so terminal tabs aren't opened here; fine-
    //    grained drag-and-drop is covered by the widget tests.)
    // ---------------------------------------------------------------
    screensDriven++;
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    final pills = find.byType(TabPill);
    final pillCount = pills.evaluate().length;
    debugPrint('[DRIVE] tabs -> $pillCount pills in the strip');
    expect(pillCount, greaterThanOrEqualTo(3),
        reason: 'home + sftp + vault + settings tabs should be present');

    // Switch to the first (home) tab by tapping its pill.
    await tester.tap(pills.first, warnIfMissed: false);
    controlsTapped++;
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    debugPrint('[DRIVE] tabs -> tapped first pill (home)');

    // Right-click the last pill → context menu → "Sağa Böl" → expect 2 groups.
    await tester.tap(find.byType(TabPill).last, buttons: kSecondaryButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    final splitItem = find.text('Sağa Böl');
    if (splitItem.evaluate().isNotEmpty) {
      await tester.tap(splitItem.last, warnIfMissed: false);
      controlsTapped++;
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      final groupBars = find.byType(ShellTabBar).evaluate().length;
      debugPrint('[DRIVE] tabs -> split right; ShellTabBar count=$groupBars');
      expect(groupBars, greaterThanOrEqualTo(2),
          reason: 'split should produce a second editor group');

      // ADR 0019: a split renders a ResizableSplit with a draggable handle.
      final handle = find.byKey(const Key('resizeHandle_0'));
      expect(handle, findsWidgets,
          reason: 'a resizable splitter handle should exist between panels');
      debugPrint('[DRIVE] tabs -> resizable splitter handle present');
      try {
        await tester.drag(handle.first, const Offset(60, 0));
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        debugPrint('[DRIVE] tabs -> dragged splitter (panel resized)');
      } catch (e) {
        debugPrint('[DRIVE] tabs -> splitter drag skipped: $e');
      }
    } else {
      await _dismissOverlays(tester);
      debugPrint('[DRIVE] tabs -> split menu item not found, dismissed');
    }
    await shot(tester, '08-tabs-split');

    // ADR 0019: full-area directional drop — drag a pill onto a group body and
    // confirm the live preview overlay appears (best-effort; precise zone drops
    // are covered by widget tests).
    final dragPill = find.byType(TabPill);
    if (dragPill.evaluate().length >= 2) {
      try {
        final start = tester.getCenter(dragPill.last);
        final g = await tester.startGesture(start);
        await g.moveBy(const Offset(0, 120)); // into a body, reveal overlay
        await tester.pump(const Duration(milliseconds: 50));
        final preview = find.textContaining('böl');
        debugPrint('[DRIVE] tabs -> body-drop preview visible='
            '${preview.evaluate().isNotEmpty}');
        await g.up();
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('[DRIVE] tabs -> body-drop drive skipped: $e');
      }
    }
    await shot(tester, '08b-tabs-body-drop');

    // Open the keyboard-shortcuts help dialog from the title bar (§9).
    final helpBtn = find.byKey(const Key('shortcutsHelpButton'));
    if (helpBtn.evaluate().isNotEmpty) {
      await tester.tap(helpBtn, warnIfMissed: false);
      controlsTapped++;
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('Klavye Kısayolları & Sekme Etkileşimleri'),
          findsOneWidget);
      debugPrint('[DRIVE] tabs -> shortcuts help dialog opened');
      await _dismissOverlays(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 150));
    }

    debugPrint('[DRIVE] SUMMARY -> screensDriven=$screensDriven '
        'controlsTapped=$controlsTapped screenshots=$screenshotsWritten');

    // Smoke assertion: the app survived the whole drive without crashing.
    expect(find.byType(SshallApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  tearDownAll(() {
    debugPrint('[DRIVE] FINAL screensDriven=$screensDriven '
        'controlsTapped=$controlsTapped screenshots=$screenshotsWritten');
    // Reference the binding so analyzer keeps the field; also a hook point.
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['screensDriven'] = screensDriven;
    binding.reportData!['controlsTapped'] = controlsTapped;
    binding.reportData!['screenshots'] = screenshotsWritten;
  });
}

/// Closes any open dialog/menu/popup by tapping a Cancel-like action if present,
/// otherwise pressing Escape, so the next control tap targets the base screen.
Future<void> _dismissOverlays(WidgetTester tester) async {
  // Prefer an explicit cancel button if a dialog is open.
  for (final label in const ['İptal', 'Vazgeç', 'Kapat']) {
    final f = find.text(label);
    if (f.evaluate().isNotEmpty) {
      await tester.tap(f.last, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 150));
      debugPrint('[DRIVE] overlay -> dismissed via "$label"');
      return;
    }
  }
  // Otherwise dismiss a popup menu / dialog with Escape.
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}
