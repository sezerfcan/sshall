import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/settings/app_settings.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/features/shell/shell_shortcuts.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/theme/app_colors.dart';

class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  @override
  Stream<WorkerEvent> get events => _c.stream;
  @override
  WorkerEvent? get currentLifecycle => null;
  @override
  void sendInput(Uint8List data) {}
  @override
  void resize(int w, int h, int pw, int ph) {}
  @override
  void decideHostKey(bool accept) {}
  @override
  Uint8List takeOutputBacklog() => Uint8List(0);
  @override
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}

void main() {
  late ProviderContainer container;
  late TabsController c;

  setUp(() {
    container = ProviderContainer();
    c = container.read(tabsControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  TabsState st() => container.read(tabsControllerProvider);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // A theme is needed so the confirm-on-close dialog (ADR 0038 D7) can
          // render via context.c if a live session is being closed.
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: ShellShortcuts(child: SizedBox.expand())),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool control = false,
    bool shift = false,
  }) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  testWidgets('Cmd+W closes the active tab', (tester) async {
    // Disable the confirm-on-close gate here so Cmd+W closes immediately; the
    // confirm path is covered by close_tab_confirm_test.dart (ADR 0038 D7).
    container
        .read(appSettingsControllerProvider.notifier)
        .setConfirmOnCloseLiveSession(false);
    final id = c.openTerminal(_FakeSession(), 'a');
    await pump(tester);
    expect(st().activeTab!.id, id);
    await press(tester, LogicalKeyboardKey.keyW, meta: true);
    await tester.pumpAndSettle();
    expect(st().tabs.containsKey(id), isFalse);
  });

  testWidgets('Cmd+\\ splits the active group right', (tester) async {
    c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b'); // a + b, >=2 tabs
    await pump(tester);
    expect(st().groups.length, 1);
    await press(tester, LogicalKeyboardKey.backslash, meta: true);
    expect(st().groups.length, 2);
  });

  testWidgets('Ctrl+Tab cycles to the previously-active tab', (tester) async {
    final a = c.openTerminal(_FakeSession(), 'a');
    final b = c.openTerminal(_FakeSession(), 'b'); // active b; MRU b,a,home
    await pump(tester);
    expect(st().activeTab!.id, b);
    await press(tester, LogicalKeyboardKey.tab, control: true);
    expect(st().activeTab!.id, a);
  });

  testWidgets('Cmd+Shift+] activates the next tab in the group (wraps)', (
    tester,
  ) async {
    final a = c.openTerminal(_FakeSession(), 'a');
    final b = c.openTerminal(_FakeSession(), 'b'); // a,b active b
    await pump(tester);
    await press(
      tester,
      LogicalKeyboardKey.bracketRight,
      meta: true,
      shift: true,
    );
    // From b (last), next wraps to a.
    expect(st().activeTab!.id, a);
    expect(st().activeTab!.id, isNot(b));
  });

  testWidgets('Cmd+5 / Cmd+6 focus editor groups by index', (tester) async {
    // ADR 0030 D7 reassigns Cmd+1..4 to rail destinations; editor-group focus
    // moves to Cmd+5..9 (digit5 → group index 0).
    c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b');
    c.splitRight(); // 2 groups
    await pump(tester);
    await press(tester, LogicalKeyboardKey.digit5, meta: true);
    expect(st().activeGroupId, st().groups[0].id);
    await press(tester, LogicalKeyboardKey.digit6, meta: true);
    expect(st().activeGroupId, st().groups[1].id);
  });

  testWidgets('Cmd+T opens the new-session launcher (home), not reopen', (
    tester,
  ) async {
    c.openTerminal(_FakeSession(), 'a'); // a session is open
    await pump(tester);
    container.read(homeRequestedProvider.notifier).state = false;
    await press(tester, LogicalKeyboardKey.keyT, meta: true);
    // Cmd+T surfaces the connection home/welcome (new-session launcher) — it
    // does NOT reopen a closed tab and does NOT create a tab.
    expect(container.read(homeRequestedProvider), isTrue);
    expect(st().tabs.length, 1); // no new tab persisted
  });

  testWidgets('Cmd+Shift+\\ merges a split; Cmd+\\ still splits', (
    tester,
  ) async {
    c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b'); // >=2 tabs
    await pump(tester);
    // Cmd+\ splits.
    await press(tester, LogicalKeyboardKey.backslash, meta: true);
    expect(st().groups.length, 2);
    // Cmd+Shift+\ merges back to one group (the dead unsplit() is now reachable).
    await press(tester, LogicalKeyboardKey.backslash, meta: true, shift: true);
    expect(st().groups.length, 1);
  });

  testWidgets('Cmd+Shift+T reopens the last closed session tab', (
    tester,
  ) async {
    c.openOrFocus(TabKind.sftp);
    final sftpId = st().activeTab!.id;
    c.close(sftpId);
    await pump(tester);
    expect(st().tabs.values.any((t) => t.kind == TabKind.sftp), isFalse);
    await press(tester, LogicalKeyboardKey.keyT, meta: true, shift: true);
    expect(st().tabs.values.any((t) => t.kind == TabKind.sftp), isTrue);
  });

  testWidgets('Cmd+, opens the Settings overlay', (tester) async {
    await pump(tester);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
    await press(tester, LogicalKeyboardKey.comma, meta: true);
    expect(container.read(activeOverlayProvider), ShellOverlay.settings);
  });

  testWidgets('Cmd+1 activates Connections (home requested, panel visible)', (
    tester,
  ) async {
    await pump(tester);
    container.read(homeRequestedProvider.notifier).state = false;
    container.read(sidebarControllerProvider.notifier).setCollapsed(true);

    await press(tester, LogicalKeyboardKey.digit1, meta: true);

    expect(container.read(homeRequestedProvider), isTrue);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
    expect(container.read(sidebarVisibleProvider), isTrue);
  });

  testWidgets('Cmd+3 / Cmd+4 toggle the Vault / Settings overlays', (
    tester,
  ) async {
    await pump(tester);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);

    await press(tester, LogicalKeyboardKey.digit3, meta: true);
    expect(container.read(activeOverlayProvider), ShellOverlay.vault);

    await press(tester, LogicalKeyboardKey.digit4, meta: true);
    expect(container.read(activeOverlayProvider), ShellOverlay.settings);
  });

  testWidgets(
    'Cmd+2 (SFTP) with no session surfaces the Connections panel + hint, '
    'not an empty tab',
    (tester) async {
      await pump(tester);
      expect(container.read(tabsControllerProvider).hasSessions, isFalse);

      await press(tester, LogicalKeyboardKey.digit2, meta: true);

      // No SFTP placeholder tab was opened.
      expect(
        container
            .read(tabsControllerProvider)
            .tabs
            .values
            .any((t) => t.kind == TabKind.sftp),
        isFalse,
      );
      // Panel is visible and the inline hint is set (D9b).
      expect(container.read(sidebarVisibleProvider), isTrue);
      expect(container.read(sidebarHintProvider), 'SFTP için bir host seçin');
    },
  );

  testWidgets('Cmd+2 (SFTP) focuses an existing SFTP session', (tester) async {
    c.openOrFocus(TabKind.sftp);
    container.read(homeRequestedProvider.notifier).state = true;
    await pump(tester);

    await press(tester, LogicalKeyboardKey.digit2, meta: true);

    expect(container.read(homeRequestedProvider), isFalse);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
    expect(st().activeTab!.kind, TabKind.sftp);
    // No hint when an actual session exists.
    expect(container.read(sidebarHintProvider), isNull);
  });

  testWidgets('Cmd +/-/0 zoom the active terminal', (tester) async {
    final id = c.openTerminal(_FakeSession(), 'a');
    await pump(tester);
    final ctrl = c.controllerFor(id)!;
    final base = ctrl.fontSize.value;
    await press(tester, LogicalKeyboardKey.equal, meta: true);
    expect(ctrl.fontSize.value, greaterThan(base));
    await press(tester, LogicalKeyboardKey.minus, meta: true);
    await press(tester, LogicalKeyboardKey.minus, meta: true);
    expect(ctrl.fontSize.value, lessThan(base));
    await press(tester, LogicalKeyboardKey.digit0, meta: true);
    expect(ctrl.fontSize.value, base);
  });
}
