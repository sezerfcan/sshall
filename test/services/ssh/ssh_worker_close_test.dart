// test/services/ssh/ssh_worker_close_test.dart
//
// Regression for the worker close path (reliability finding #3): on CloseCommand
// the isolate must deliver a final ClosedEvent BEFORE it exits. Previously the
// worker did `toUi.send(ClosedEvent()); break;` then a bare `Isolate.exit()`,
// which does NOT guarantee the queued send is delivered. The fix uses
// `Isolate.exit(toUi, ClosedEvent())`, which delivers the final message
// atomically with termination.
//
// This drives the real worker isolate directly (no SSH server needed): we never
// connect, just hand it a command port and immediately send CloseCommand.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_worker.dart';

void main() {
  test('CloseCommand delivers a final ClosedEvent before the isolate exits',
      () async {
    final fromWorker = ReceivePort();
    final events = fromWorker.asBroadcastStream();

    final handshake = Completer<SendPort>();
    final closed = Completer<void>();
    final sub = events.listen((msg) {
      if (msg is SendPort && !handshake.isCompleted) {
        handshake.complete(msg);
      } else if (msg is ClosedEvent && !closed.isCompleted) {
        closed.complete();
      }
    });

    await Isolate.spawn(sshWorkerMain, fromWorker.sendPort);
    final toWorker =
        await handshake.future.timeout(const Duration(seconds: 10));

    // Never connect; go straight to close. The final ClosedEvent must still
    // arrive even though the isolate exits immediately after sending it.
    toWorker.send(CloseCommand());

    await closed.future.timeout(const Duration(seconds: 10),
        onTimeout: () =>
            fail('ClosedEvent was not delivered before isolate exit'));

    await sub.cancel();
    fromWorker.close();
  });
}
