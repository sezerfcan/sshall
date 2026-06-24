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
  final List<Uint8List> sentInput = [];
  Uint8List backlog = Uint8List(0);

  void emit(WorkerEvent e) => _c.add(e);

  @override
  Stream<WorkerEvent> get events => _c.stream;
  @override
  WorkerEvent? get currentLifecycle => null;
  @override
  void sendInput(Uint8List data) => sentInput.add(data);
  @override
  void resize(int w, int h, int pw, int ph) {}
  @override
  void decideHostKey(bool accept) {}
  @override
  Uint8List takeOutputBacklog() => backlog;
  @override
  Future<void> close() async {
    closeCalls++;
    if (!_c.isClosed) await _c.close();
  }
}

void main() {
  test('status starts in connecting (tab opens immediately — D2)', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);
    expect(c.status.value.state, SessionState.connecting);
    await c.dispose();
  });

  test('StatusEvent translation: authenticating → connected', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);

    s.emit(StatusEvent(SshStatus.authenticating));
    await Future<void>.delayed(Duration.zero);
    expect(c.status.value.state, SessionState.authenticating);

    s.emit(StatusEvent(SshStatus.ready));
    await Future<void>.delayed(Duration.zero);
    expect(c.status.value.state, SessionState.connected);

    await c.dispose();
  });

  test(
    'ErrorEvent → error+cause+raw; NO red [sshall] line written (D3)',
    () async {
      final s = _FakeSession();
      final c = TerminalSessionController(s);

      s.emit(ErrorEvent('auth', 'bad creds'));
      await Future<void>.delayed(Duration.zero);
      expect(c.status.value.state, SessionState.error);
      expect(c.status.value.cause, ErrorCause.auth);
      expect(c.status.value.rawMessage, 'bad creds');

      // The error card surfaces the message now; the terminal must not contain a
      // raw red [sshall] line (D3 regression guard).
      final dump = c.terminal.buffer.toString();
      expect(dump.contains('[sshall]'), isFalse);

      await c.dispose();
    },
  );

  test(
    'unexpected ClosedEvent → disconnected drop (reconnect offered, D1)',
    () async {
      final s = _FakeSession();
      final c = TerminalSessionController(s);
      s.emit(ClosedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(c.status.value.state, SessionState.disconnected);
      expect(c.status.value.userInitiated, isFalse);
      expect(c.status.value.canReconnect, isTrue);
      await c.dispose();
    },
  );

  test('a bare closed StatusEvent on a torn-down session is a drop', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);
    s.emit(StatusEvent(SshStatus.closed));
    await Future<void>.delayed(Duration.zero);
    expect(c.status.value.state, SessionState.disconnected);
    expect(c.status.value.userInitiated, isFalse);
    await c.dispose();
  });

  test('error status is not overwritten by a trailing ClosedEvent', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);
    s.emit(ErrorEvent('network', 'Connection refused'));
    s.emit(ClosedEvent());
    await Future<void>.delayed(Duration.zero);
    // The card must keep the cause; the trailing close must not flatten it.
    expect(c.status.value.state, SessionState.error);
    expect(c.status.value.cause, ErrorCause.refused);
    await c.dispose();
  });

  test(
    'prior scrollback survives an error (freeze under the card — D3)',
    () async {
      final s = _FakeSession();
      final c = TerminalSessionController(s);
      s.emit(OutputEvent(Uint8List.fromList('hello world\r\n'.codeUnits)));
      await Future<void>.delayed(Duration.zero);
      s.emit(ErrorEvent('network', 'boom'));
      await Future<void>.delayed(Duration.zero);
      final dump = c.terminal.buffer.toString();
      expect(
        dump.contains('hello world'),
        isTrue,
        reason: 'scrollback is not cleared on error',
      );
      await c.dispose();
    },
  );

  test('zoom in/out/reset clamps to [kFontMin, kFontMax]', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);
    expect(c.fontSize.value, kFontDefault);

    c.zoomIn();
    expect(c.fontSize.value, kFontDefault + kFontStep);

    c.zoomReset();
    expect(c.fontSize.value, kFontDefault);

    for (var i = 0; i < 100; i++) {
      c.zoomOut();
    }
    expect(c.fontSize.value, kFontMin);

    for (var i = 0; i < 100; i++) {
      c.zoomIn();
    }
    expect(c.fontSize.value, kFontMax);

    await c.dispose();
  });

  test(
    'proxy taps forward raw output and legacy status token (ADR 0020)',
    () async {
      final s = _FakeSession();
      final c = TerminalSessionController(s);
      final out = <int>[];
      final statuses = <String>[];
      c.onRawOutput = out.addAll;
      c.onStatusChange = statuses.add;

      s.emit(OutputEvent(Uint8List.fromList([104, 105])));
      s.emit(StatusEvent(SshStatus.ready));
      s.emit(ClosedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(out, [104, 105], reason: 'raw bytes forwarded to the window');
      // Backward-compatible string token (rich-model parity is pass-2).
      expect(statuses, contains('connected'));
      expect(statuses, contains('disconnected'));
      await c.dispose();
    },
  );

  test(
    'reconnect() re-runs the stored thunk on the same controller (D5)',
    () async {
      final s = _FakeSession();
      var calls = 0;
      final c = TerminalSessionController(
        s,
        reconnectThunk: () async => calls++,
      );
      expect(c.canReconnect, isTrue);
      await c.reconnect();
      expect(calls, 1);
      await c.dispose();
    },
  );

  test('reconnect is a no-op without a thunk', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);
    expect(c.canReconnect, isFalse);
    await c.reconnect(); // must not throw
    await c.dispose();
  });

  test(
    'rebind swaps the session, resets to connecting, reuses terminal (D5)',
    () async {
      final s1 = _FakeSession();
      final c = TerminalSessionController(s1);
      s1.emit(OutputEvent(Uint8List.fromList('keep-me\r\n'.codeUnits)));
      await Future<void>.delayed(Duration.zero);
      s1.emit(ErrorEvent('network', 'boom'));
      await Future<void>.delayed(Duration.zero);
      expect(c.status.value.state, SessionState.error);

      final s2 = _FakeSession();
      await c.rebind(s2);
      expect(c.status.value.state, SessionState.connecting);
      // Scrollback survives the reconnect (same xterm.Terminal).
      expect(c.terminal.buffer.toString().contains('keep-me'), isTrue);
      // New session is wired: an event on s2 reaches the controller.
      s2.emit(StatusEvent(SshStatus.ready));
      await Future<void>.delayed(Duration.zero);
      expect(c.status.value.state, SessionState.connected);
      // Old session was closed.
      expect(s1.closeCalls, greaterThanOrEqualTo(1));

      await c.dispose();
    },
  );

  test('dispose is idempotent and closes the session once', () async {
    final s = _FakeSession();
    final c = TerminalSessionController(s);
    await c.dispose();
    await c.dispose();
    expect(s.closeCalls, 1);
  });
}
