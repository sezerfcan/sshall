import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';

import '../ssh/ssh_messages.dart';
import '../ssh/terminal_session.dart';

/// Adapts a [Pty] (flutter_pty) to the [TerminalSession] contract so a LOCAL
/// `docker exec -it` runs in the same xterm pane as a remote SSH shell. The
/// PTY's output becomes [OutputEvent]s, its exit becomes a [ClosedEvent], and a
/// [StatusEvent] ready is emitted immediately (a local exec has no async connect
/// or host-key step). See ADR 0028/0029.
class PtyTerminalSession implements TerminalSession {
  final void Function(Uint8List data) _write;
  final void Function(int rows, int cols) _resize;
  final void Function() _kill;

  final StreamController<WorkerEvent> _events =
      StreamController<WorkerEvent>.broadcast();
  final BytesBuilder _backlog = BytesBuilder(copy: false);
  bool _backlogConsumed = false;
  WorkerEvent? _lastLifecycle;

  PtyTerminalSession._(
    this._write,
    this._resize,
    this._kill,
    Stream<Uint8List> output,
    Future<int> exitCode,
  ) {
    output.listen((d) => _emit(OutputEvent(d)));
    exitCode
        .then((_) => _emit(ClosedEvent()))
        .catchError((_) => _emit(ClosedEvent()));
    _emit(StatusEvent(SshStatus.ready));
  }

  /// Spawns [executable] with [arguments] in a real PTY.
  factory PtyTerminalSession.start(
    String executable, {
    required List<String> arguments,
    int rows = 24,
    int columns = 80,
  }) {
    final pty = Pty.start(executable,
        arguments: arguments, rows: rows, columns: columns);
    return PtyTerminalSession._(
      pty.write,
      pty.resize,
      // flutter_pty's Pty.kill is `bool kill([ProcessSignal])`, not a
      // `void Function()`, so wrap it to fit the adapter's _kill seam.
      () => pty.kill(),
      pty.output,
      pty.exitCode,
    );
  }

  /// Test seam: drive the adapter with in-memory streams instead of a native PTY.
  @visibleForTesting
  factory PtyTerminalSession.test({
    required Stream<Uint8List> output,
    required void Function(Uint8List data) onWrite,
    required Future<int> exitCode,
    void Function(int rows, int cols)? onResize,
    void Function()? onKill,
  }) =>
      PtyTerminalSession._(
        onWrite,
        onResize ?? (_, __) {},
        onKill ?? () {},
        output,
        exitCode,
      );

  void _emit(WorkerEvent e) {
    if (e is OutputEvent && !_backlogConsumed) _backlog.add(e.data);
    if (e is StatusEvent || e is ClosedEvent || e is ErrorEvent) {
      if (_lastLifecycle is! ClosedEvent && _lastLifecycle is! ErrorEvent) {
        _lastLifecycle = e;
      }
    }
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Stream<WorkerEvent> get events => _events.stream;

  @override
  WorkerEvent? get currentLifecycle => _lastLifecycle;

  @override
  Uint8List takeOutputBacklog() {
    _backlogConsumed = true;
    return _backlog.takeBytes();
  }

  @override
  void sendInput(Uint8List data) => _write(data);

  @override
  void resize(int w, int h, int pw, int ph) => _resize(h, w);

  @override
  void decideHostKey(bool accept) {} // no host key for a local PTY

  @override
  Future<void> close() async {
    _kill();
    if (!_events.isClosed) await _events.close();
  }
}
