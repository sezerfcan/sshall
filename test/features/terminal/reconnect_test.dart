import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/terminal_session_controller.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';

class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  int closeCalls = 0;
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
    closeCalls++;
    if (!_c.isClosed) await _c.close();
  }
}

void main() {
  test('reconnect() opens a new session via the stored thunk (D5)', () async {
    final s1 = _FakeSession();
    final newSessions = <_FakeSession>[];
    late TerminalSessionController c;
    c = TerminalSessionController(
      s1,
      hostPort: 'web1:22',
      reconnectThunk: () async {
        final next = _FakeSession();
        newSessions.add(next);
        await c.rebind(next);
      },
    );

    // Drive to an error first (a realistic reconnect entry point).
    s1.emit(ErrorEvent('network', 'Connection refused'));
    await Future<void>.delayed(Duration.zero);
    expect(c.status.value.state, SessionState.error);

    await c.reconnect();
    expect(newSessions, hasLength(1));
    // New session is connecting and wired.
    expect(c.status.value.state, SessionState.connecting);
    newSessions.first.emit(StatusEvent(SshStatus.ready));
    await Future<void>.delayed(Duration.zero);
    expect(c.status.value.state, SessionState.connected);

    await c.dispose();
  });

  test(
    'scrollback is preserved across reconnect (same terminal — D5)',
    () async {
      final s1 = _FakeSession();
      late TerminalSessionController c;
      c = TerminalSessionController(
        s1,
        reconnectThunk: () async => c.rebind(_FakeSession()),
      );
      s1.emit(
        OutputEvent(Uint8List.fromList('SESSION-1-OUTPUT\r\n'.codeUnits)),
      );
      await Future<void>.delayed(Duration.zero);
      s1.emit(ClosedEvent());
      await Future<void>.delayed(Duration.zero);

      await c.reconnect();
      expect(
        c.terminal.buffer.toString().contains('SESSION-1-OUTPUT'),
        isTrue,
        reason: 'the same xterm.Terminal is reused, so scrollback survives',
      );
      await c.dispose();
    },
  );

  test('NO auto-reconnect after auth failure (security, D5)', () async {
    final s = _FakeSession();
    var thunkCalls = 0;
    final c = TerminalSessionController(
      s,
      reconnectThunk: () async => thunkCalls++,
    );
    s.emit(ErrorEvent('auth', 'denied'));
    await Future<void>.delayed(Duration.zero);
    // The error sets state but NEVER auto-invokes the reconnect thunk.
    expect(c.status.value.cause, ErrorCause.auth);
    expect(thunkCalls, 0, reason: 'auth failure must not auto-reconnect');
    await c.dispose();
  });

  test('NO auto-reconnect after host-key mismatch (security, D5)', () async {
    final s = _FakeSession();
    var thunkCalls = 0;
    final c = TerminalSessionController(
      s,
      reconnectThunk: () async => thunkCalls++,
    );
    s.emit(ErrorEvent('hostkey', 'Host key rejected'));
    await Future<void>.delayed(Duration.zero);
    expect(c.status.value.cause, ErrorCause.hostKeyMismatch);
    expect(thunkCalls, 0, reason: 'host-key mismatch must not auto-reconnect');
    await c.dispose();
  });

  test('reconnect works normally after a clean (user) disconnect', () async {
    final s = _FakeSession();
    var thunkCalls = 0;
    final c = TerminalSessionController(
      s,
      reconnectThunk: () async => thunkCalls++,
    );
    await c.reconnect(); // manual call always allowed
    expect(thunkCalls, 1);
    await c.dispose();
  });
}
