import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/settings/app_settings.dart';
import 'package:sshall/features/shell/close_tab_confirm.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart';

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

/// Pumps a single button that calls [closeTabWithConfirm] for [tabId], so the
/// confirm dialog has a real Navigator + theme to render into.
Future<void> _pumpCloser(
  WidgetTester tester,
  ProviderContainer container,
  String tabId,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              key: const Key('closeBtn'),
              onPressed: () => closeTabWithConfirm(context, ref, tabId),
              child: const Text('close'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  Future<ProviderContainer> makeContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('a connected tab prompts before closing when the setting is on', (
    tester,
  ) async {
    final container = await makeContainer();
    final tabs = container.read(tabsControllerProvider.notifier);
    final id = tabs.openTerminal(_FakeSession(), 'web:22');
    // A freshly opened session is in `connecting` → counts as live.
    expect(tabs.isLiveSession(id), isTrue);

    await _pumpCloser(tester, container, id);
    await tester.tap(find.byKey(const Key('closeBtn')));
    await tester.pumpAndSettle();

    // The confirm dialog is shown; cancelling keeps the tab.
    expect(find.text('Oturumu kapat?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(container.read(tabsControllerProvider).tabs.containsKey(id), isTrue);
  });

  testWidgets('confirming the dialog closes the tab', (tester) async {
    final container = await makeContainer();
    final tabs = container.read(tabsControllerProvider.notifier);
    final id = tabs.openTerminal(_FakeSession(), 'web:22');

    await _pumpCloser(tester, container, id);
    await tester.tap(find.byKey(const Key('closeBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmCloseTab')));
    await tester.pumpAndSettle();
    expect(
      container.read(tabsControllerProvider).tabs.containsKey(id),
      isFalse,
    );
  });

  testWidgets('with the setting off, a live tab closes WITHOUT a prompt', (
    tester,
  ) async {
    final container = await makeContainer();
    container
        .read(appSettingsControllerProvider.notifier)
        .setConfirmOnCloseLiveSession(false);
    final tabs = container.read(tabsControllerProvider.notifier);
    final id = tabs.openTerminal(_FakeSession(), 'web:22');

    await _pumpCloser(tester, container, id);
    await tester.tap(find.byKey(const Key('closeBtn')));
    await tester.pumpAndSettle();

    // No dialog; the tab is gone immediately (previous behavior preserved).
    expect(find.text('Oturumu kapat?'), findsNothing);
    expect(
      container.read(tabsControllerProvider).tabs.containsKey(id),
      isFalse,
    );
  });
}
