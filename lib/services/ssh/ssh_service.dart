import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ssh_messages.dart';
import 'ssh_worker.dart';
import 'terminal_session.dart';

class SshSession implements TerminalSession {
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final StreamController<WorkerEvent> _events =
      StreamController<WorkerEvent>.broadcast();
  final BytesBuilder _backlog = BytesBuilder(copy: false);
  bool _backlogConsumed = false;
  WorkerEvent? _currentLifecycle;

  SshSession._(this._toWorker, this._fromWorker);

  /// Test constructor for unit tests.
  @visibleForTesting
  SshSession.test({
    SendPort? toWorker,
    ReceivePort? fromWorker,
    WorkerEvent? currentLifecycle,
  })  : _toWorker = toWorker ?? _dummySendPort(),
        _fromWorker = fromWorker ?? _dummyReceivePort(),
        _currentLifecycle = currentLifecycle;

  static SendPort _dummySendPort() {
    final p = ReceivePort();
    final sp = p.sendPort;
    p.close();
    return sp;
  }
  static ReceivePort _dummyReceivePort() => ReceivePort();

  @override
  Stream<WorkerEvent> get events => _events.stream;

  @override
  WorkerEvent? get currentLifecycle => _currentLifecycle;

  void _emit(WorkerEvent e) {
    if (e is OutputEvent && !_backlogConsumed) _backlog.add(e.data);
    if (e is StatusEvent || e is ErrorEvent || e is HostKeyRequestEvent) {
      _currentLifecycle = e;
    }
    if (!_events.isClosed) _events.add(e);
  }

  /// Output bytes received before the terminal screen attached its listener.
  /// Call once from the terminal's initState to replay output produced during
  /// the connect->terminal handoff; buffering stops after the first call.
  @override
  Uint8List takeOutputBacklog() {
    _backlogConsumed = true;
    return _backlog.takeBytes();
  }

  @override
  void sendInput(Uint8List data) => _toWorker.send(StdinCommand(data));
  @override
  void resize(int w, int h, int pw, int ph) =>
      _toWorker.send(ResizeCommand(w, h, pw, ph));
  @override
  void decideHostKey(bool accept) =>
      _toWorker.send(HostKeyDecisionCommand(accept));

  @override
  Future<void> close() async {
    _toWorker.send(CloseCommand());
    if (!_events.isClosed) await _events.close();
    _fromWorker.close();
  }
}

class SshService {
  Future<SshSession> connect(SshConnectParams params) async {
    final fromWorker = ReceivePort();
    final handshake = Completer<SendPort>();
    SshSession? session;

    // Single, persistent listener: the worker's first message is its command
    // SendPort; every later message is a WorkerEvent forwarded to the session.
    // Set up before spawn so the SendPort message can never be missed.
    fromWorker.listen((msg) {
      if (msg is SendPort && !handshake.isCompleted) {
        handshake.complete(msg);
      } else if (msg is WorkerEvent) {
        session?._emit(msg);
      }
    });

    try {
      await Isolate.spawn(sshWorkerMain, fromWorker.sendPort);
      // Bound the handshake: if the worker entrypoint dies before sending its
      // command port, fail loudly instead of hanging the connect forever (and
      // leaking the spawned isolate + ReceivePort).
      final toWorker =
          await handshake.future.timeout(const Duration(seconds: 10));
      session = SshSession._(toWorker, fromWorker);
      toWorker.send(ConnectCommand(params));
      return session;
    } catch (_) {
      fromWorker.close();
      rethrow;
    }
  }
}
