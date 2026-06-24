import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('renders the xterm canvas and status bar once connected', (
    tester,
  ) async {
    final s = _FakeSession();
    final ctrl = TerminalSessionController(s);
    await tester.pumpWidget(host(ctrl));
    s.emit(StatusEvent(SshStatus.ready));
    await tester.pump();
    // Localized status label (D7): connected → "Bağlı".
    expect(find.text('Bağlı'), findsOneWidget);
    expect(find.text('13pt'), findsOneWidget); // zoom label
    // dispose() closes a broadcast StreamController; that future only settles on
    // the real event loop, so it must run via runAsync.
    await tester.runAsync(() => ctrl.dispose());
  });

  testWidgets('zoom in button increases font size label', (tester) async {
    final s = _FakeSession();
    final ctrl = TerminalSessionController(s);
    await tester.pumpWidget(host(ctrl));
    s.emit(StatusEvent(SshStatus.ready));
    await tester.pump();
    expect(find.text('13pt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('zoomIn')));
    await tester.pump();
    expect(find.text('14pt'), findsOneWidget);
    await tester.runAsync(() => ctrl.dispose());
  });
}
