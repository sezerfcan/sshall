import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/connection_error_card.dart';
import 'package:sshall/features/terminal/terminal_session_controller.dart';
import 'package:sshall/features/terminal/terminal_view.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/terminal_session.dart';
import 'package:sshall/theme/app_colors.dart';

/// A Docker exec-style [TerminalSession] (not an SshSession): proves the shared
/// controller/view routing (ADR 0032 D3 — "route SSH AND Docker connect
/// failures through the same component") works for any TerminalSession, which
/// is exactly what a container exec is (SshSession remote / PtyTerminalSession
/// local).
class _FakeDockerSession implements TerminalSession {
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

  testWidgets(
    'Docker exec connect failure → in-pane error card, not SnackBar',
    (tester) async {
      final s = _FakeDockerSession();
      final ctrl = TerminalSessionController(s, hostPort: 'docker-host:22');
      await tester.pumpWidget(host(ctrl));
      await tester.pump();

      s.emit(ErrorEvent('network', 'Connection refused'));
      await tester.pump();

      expect(find.byType(ConnectionErrorCard), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.runAsync(() => ctrl.dispose());
    },
  );

  testWidgets('Docker-specific raw error is kept in Detaylar (unknown cause)', (
    tester,
  ) async {
    final s = _FakeDockerSession();
    final ctrl = TerminalSessionController(s, hostPort: 'docker-host:22');
    await tester.pumpWidget(host(ctrl));
    await tester.pump();

    // A daemon-not-running style failure has no precise cause → unknown, but
    // the raw message must remain accessible in Detaylar (D4/D9).
    s.emit(ErrorEvent('unknown', 'Cannot connect to the Docker daemon'));
    await tester.pump();

    expect(find.byType(ConnectionErrorCard), findsOneWidget);
    await tester.tap(find.byKey(const Key('errorDetailsToggle')));
    await tester.pump();
    expect(find.text('Cannot connect to the Docker daemon'), findsOneWidget);
    await tester.runAsync(() => ctrl.dispose());
  });
}
