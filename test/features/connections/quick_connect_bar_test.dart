import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/features/connections/quick_connect_bar.dart';
import 'package:sshall/theme/app_colors.dart';

/// Widget coverage for the omnibox Quick Connect bar (ADR 0034 D1/D3/D4): the
/// placeholder + help + clear affordances, the no-silent-no-op empty submit,
/// inline host/port validation, suggestions + keyboard navigation, and the
/// leading spinner while in flight.
Connection _conn(String id, String label, String host) => Connection(
  id: id,
  label: label,
  host: host,
  folderId: null,
  username: 'root',
  port: 22,
  authRef: 'i$id',
  tags: const [],
  order: 0,
);

void main() {
  late List<String> connected;
  late List<String> removed;
  late int cleared;

  Future<void> pump(
    WidgetTester tester, {
    List<String> recents = const [],
    List<Connection> saved = const [],
    Future<void> Function(String)? onConnect,
  }) {
    connected = [];
    removed = [];
    cleared = 0;
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: QuickConnectBar(
              onConnectTarget:
                  onConnect ??
                  (t) async {
                    connected.add(t);
                  },
              recents: recents,
              saved: saved,
              displayOf: (c) => c.label,
              targetOf: (c) => 'root@${c.host}:22',
              hostOf: (c) => c.host,
              onRemoveRecent: (t) => removed.add(t),
              onClearHistory: () => cleared++,
            ),
          ),
        ),
      ),
    );
  }

  Finder field() => find.byKey(const Key('quickConnectInput'));

  testWidgets('(a) shows the mono grammar placeholder + help icon (§9)', (
    tester,
  ) async {
    await pump(tester);
    final tf = tester.widget<TextField>(field());
    expect(
      tf.decoration!.hintText,
      'kullanıcı@host:port · ssh user@host -p 22',
    );
    expect(find.byKey(const Key('quickConnectHelp')), findsOneWidget);

    // Tapping help opens a popover listing the accepted forms.
    await tester.tap(find.byKey(const Key('quickConnectHelp')));
    await tester.pumpAndSettle();
    expect(find.text('Kabul edilen biçimler'), findsOneWidget);
    expect(find.text('kullanıcı@host:port'), findsOneWidget);
    expect(find.text('ssh user@host -p N'), findsOneWidget);
  });

  testWidgets(
    '(b) clear (x) appears only with text; clears + reopens recents',
    (tester) async {
      await pump(tester, recents: ['root@a.com:22']);
      // Empty: no clear button.
      expect(find.byKey(const Key('quickConnectClear')), findsNothing);

      await tester.enterText(field(), 'root@b.com');
      await tester.pump();
      expect(find.byKey(const Key('quickConnectClear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('quickConnectClear')));
      await tester.pump();
      // Field empties.
      expect(tester.widget<TextField>(field()).controller!.text, '');
      // Recents dropdown reopened (focus kept).
      expect(find.byKey(const Key('quickSuggestionsDropdown')), findsOneWidget);
    },
  );

  testWidgets(
    '(c) empty submit is never silent: dropdown when history exists',
    (tester) async {
      await pump(tester, recents: ['root@a.com:22']);
      await tester.tap(field());
      await tester.pump();
      // Focusing the empty bar opens the recents dropdown.
      expect(find.byKey(const Key('quickSuggestionsDropdown')), findsOneWidget);
    },
  );

  testWidgets('(c) empty submit with NO history shows an inline hint', (
    tester,
  ) async {
    await pump(tester); // no recents, no saved
    await tester.tap(field());
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byKey(const Key('quickConnectHint')), findsOneWidget);
  });

  testWidgets('(d) inline errors: no host, bad port; cleared live on fix', (
    tester,
  ) async {
    await pump(tester);
    // No host parseable (a lone "@") → host error.
    await tester.enterText(field(), '@');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Metinde bir host bulunamadı'), findsOneWidget);

    // Out-of-range port → port error.
    await tester.enterText(field(), 'host.com:70000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Port 1–65535 olmalı'), findsOneWidget);

    // Typing a valid target live-clears the error.
    await tester.enterText(field(), 'host.com:22');
    await tester.pump();
    expect(find.text('Port 1–65535 olmalı'), findsNothing);
  });

  testWidgets('(d) incomplete-but-valid (host, no cred) is NOT an error', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field(), 'fresh.example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // No error styling: the view will silently fall back to the dialog.
    expect(find.byKey(const Key('quickConnectError')), findsNothing);
    // It DID attempt a connect/route (not a silent no-op).
    expect(connected, ['fresh.example.com']);
  });

  testWidgets('(e) keyboard: Down/Up move highlight, Tab accepts, Esc closes', (
    tester,
  ) async {
    await pump(
      tester,
      recents: ['root@a.com:22'],
      saved: [_conn('1', 'web', 'web.com')],
    );
    await tester.tap(field());
    await tester.pump();
    expect(find.byKey(const Key('quickSuggestionsDropdown')), findsOneWidget);

    // Down highlights the first suggestion; Tab accepts it into the field.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<TextField>(field()).controller!.text, 'root@a.com:22');

    // Esc closes the dropdown.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('quickSuggestionsDropdown')), findsNothing);
  });

  testWidgets('(e) Enter connects the highlighted suggestion', (tester) async {
    await pump(tester, saved: [_conn('1', 'web', 'web.com')]);
    await tester.tap(field());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(connected, ['root@web.com:22']);
  });

  testWidgets('(e) Enter connects the typed target when nothing highlighted', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field(), 'root@typed.com:22');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(connected, ['root@typed.com:22']);
  });

  testWidgets('(f) leading icon swaps bolt → spinner while in flight', (
    tester,
  ) async {
    // A connect that we hold open so the spinner is observable.
    final gate = Completer<void>();
    await pump(tester, onConnect: (t) => gate.future);
    await tester.enterText(field(), 'root@host.com:22');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('quickConnectSpinner')), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('per-recent remove + clear-history wire through', (tester) async {
    await pump(tester, recents: ['root@a.com:22', 'root@b.com:22']);
    await tester.tap(field());
    await tester.pump();
    await tester.tap(find.byKey(const Key('removeRecent-0')));
    expect(removed, ['root@a.com:22']);
    await tester.tap(find.byKey(const Key('clearHistory')));
    expect(cleared, 1);
  });
}
