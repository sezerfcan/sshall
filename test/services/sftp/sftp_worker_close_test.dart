// test/services/sftp/sftp_worker_close_test.dart
//
// Regression for the worker close path (reliability finding #3): on SftpClose
// the isolate must deliver a final SftpClosedEvent BEFORE it exits. Previously
// the worker did `toUi.send(SftpClosedEvent()); break;` then a bare
// `Isolate.exit()`, which does NOT guarantee the queued send is delivered — the
// isolate could die first, leaving UI-side RPC Completers hung (never failed by
// _failPending). The fix uses `Isolate.exit(toUi, SftpClosedEvent())`, which
// delivers the final message atomically with termination.
//
// This drives the real worker isolate directly (no SSH server needed): we never
// connect, just hand it a command port and immediately send SftpClose.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/sftp_worker.dart';

void main() {
  test('SftpClose delivers a final SftpClosedEvent before the isolate exits',
      () async {
    final fromWorker = ReceivePort();
    final events = fromWorker.asBroadcastStream();

    // First message back from the worker is its command SendPort.
    final handshake = Completer<SendPort>();
    final closed = Completer<void>();
    final sub = events.listen((msg) {
      if (msg is SendPort && !handshake.isCompleted) {
        handshake.complete(msg);
      } else if (msg is SftpClosedEvent && !closed.isCompleted) {
        closed.complete();
      }
    });

    await Isolate.spawn(sftpWorkerMain, fromWorker.sendPort);
    final toWorker =
        await handshake.future.timeout(const Duration(seconds: 10));

    // Never connect; go straight to close. The final SftpClosedEvent must still
    // arrive even though the isolate exits immediately after sending it.
    toWorker.send(SftpClose());

    await closed.future.timeout(const Duration(seconds: 10),
        onTimeout: () =>
            fail('SftpClosedEvent was not delivered before isolate exit'));

    await sub.cancel();
    fromWorker.close();
  });
}
