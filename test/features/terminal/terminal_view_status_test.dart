import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/connecting_pane.dart';
import 'package:sshall/features/terminal/connection_error_card.dart';
import 'package:sshall/features/terminal/terminal_session_controller.dart';
import 'package:sshall/features/terminal/terminal_view.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/theme/app_colors.dart';

class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  void emit(WorkerEvent e) => _c.add(e);
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
  Widget host(TerminalSessionController ctrl) => ProviderScope(
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(body: TerminalView(controller: ctrl)),
    ),
  );

  testWidgets('connecting → ConnectingPane visible, no error card', (
    tester,
  ) async {
    final s = _FakeSession();
    final ctrl = TerminalSessionController(s, hostPort: 'web1:22');
    await tester.pumpWidget(host(ctrl));
    await tester.pump();
    expect(find.byType(ConnectingPane), findsOneWidget);
    expect(find.byType(ConnectionErrorCard), findsNothing);
    await tester.runAsync(() => ctrl.dispose());
  });

  testWidgets('connected → terminal shown, no pane/card', (tester) async {
    final s = _FakeSession();
    final ctrl = TerminalSessionController(s, hostPort: 'web1:22');
    await tester.pumpWidget(host(ctrl));
    s.emit(StatusEvent(SshStatus.ready));
    await tester.pump();
    expect(find.byType(ConnectingPane), findsNothing);
    expect(find.byType(ConnectionErrorCard), findsNothing);
    await tester.runAsync(() => ctrl.dispose());
  });

  testWidgets(
    'error → ConnectionErrorCard; prior scrollback kept under it (D3)',
    (tester) async {
      final s = _FakeSession();
      final ctrl = TerminalSessionController(s, hostPort: 'web1:22');
      await tester.pumpWidget(host(ctrl));
      s.emit(StatusEvent(SshStatus.ready));
      s.emit(OutputEvent(Uint8List.fromList('PRIOR-OUTPUT\r\n'.codeUnits)));
      await tester.pump();
      s.emit(ErrorEvent('auth', 'denied'));
      await tester.pump();
      expect(find.byType(ConnectionErrorCard), findsOneWidget);
      // The terminal (and its scrollback) is still in the tree under the card.
      expect(ctrl.terminal.buffer.toString().contains('PRIOR-OUTPUT'), isTrue);
      await tester.runAsync(() => ctrl.dispose());
    },
  );

  testWidgets('unexpected disconnect → "Bağlantı kesildi" card', (
    tester,
  ) async {
    final s = _FakeSession();
    final ctrl = TerminalSessionController(s, hostPort: 'web1:22');
    await tester.pumpWidget(host(ctrl));
    s.emit(StatusEvent(SshStatus.ready));
    await tester.pump();
    s.emit(ClosedEvent()); // not user-initiated
    await tester.pump();
    expect(find.byType(ConnectionErrorCard), findsOneWidget);
    // The card title (within the card) reads "Bağlantı kesildi". The status bar
    // also localizes the label to the same text, so scope the find to the card.
    expect(
      find.descendant(
        of: find.byType(ConnectionErrorCard),
        matching: find.text('Bağlantı kesildi'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ConnectionErrorCard),
        matching: find.text('Yeniden Bağlan'),
      ),
      findsOneWidget,
    );
    await tester.runAsync(() => ctrl.dispose());
  });

  testWidgets('status bar reconnect affordance appears on error (D7)', (
    tester,
  ) async {
    final s = _FakeSession();
    var reconnects = 0;
    final ctrl = TerminalSessionController(
      s,
      hostPort: 'web1:22',
      reconnectThunk: () async => reconnects++,
    );
    await tester.pumpWidget(host(ctrl));
    s.emit(StatusEvent(SshStatus.ready));
    await tester.pump();
    // Connected: the clickable status-bar reconnect is hidden.
    expect(find.byKey(const Key('statusReconnect')), findsNothing);
    s.emit(ErrorEvent('auth', 'denied'));
    await tester.pump();
    // Error: the status-bar dot/label become a clickable reconnect.
    expect(find.byKey(const Key('statusReconnect')), findsOneWidget);
    await tester.tap(find.byKey(const Key('statusReconnect')));
    expect(reconnects, 1);
    await tester.runAsync(() => ctrl.dispose());
  });
}
