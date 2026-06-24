import 'dart:async';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/remote_entry.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/sftp_service.dart';

void main() {
  // A fake "worker": listens for commands, replies on [reply] by RPC id.
  late ReceivePort workerInbox;     // what the session sends to
  late ReceivePort fromWorker;      // what the session listens on
  late SftpSession session;

  setUp(() {
    workerInbox = ReceivePort();
    fromWorker = ReceivePort();
    session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);
  });

  tearDown(() {
    workerInbox.close();
  });

  test('list() resolves with the reply payload matched by id', () async {
    workerInbox.listen((cmd) {
      if (cmd is SftpRpc && cmd.op is ListDir) {
        fromWorker.sendPort.send(SftpReply.ok(cmd.id, const <RemoteEntry>[
          RemoteEntry(name: 'x', path: '/x', isDir: true, isSymlink: false,
              size: 0, modified: null, mode: null),
        ]));
      }
    });
    final entries = await session.list('/');
    expect(entries.single.name, 'x');
  });

  test('concurrent requests route to the right Completer', () async {
    workerInbox.listen((cmd) {
      if (cmd is SftpRpc && cmd.op is StatOp) {
        final path = (cmd.op as StatOp).path;
        fromWorker.sendPort.send(SftpReply.ok(cmd.id, RemoteEntry(
            name: path, path: path, isDir: false, isSymlink: false,
            size: 1, modified: null, mode: null)));
      }
    });
    final a = session.stat('/a');
    final b = session.stat('/b');
    final results = await Future.wait([a, b]);
    expect(results[0]!.name, '/a');
    expect(results[1]!.name, '/b');
  });

  test('err reply surfaces as SftpException', () async {
    workerInbox.listen((cmd) {
      if (cmd is SftpRpc) {
        fromWorker.sendPort.send(SftpReply.err(cmd.id, 'perm', 'İzin yok'));
      }
    });
    expect(() => session.mkdir('/root/x'),
        throwsA(isA<SftpException>().having((e) => e.code, 'code', 'perm')));
  });

  // Reliability finding #3 (UI side): a SftpClosedEvent from the worker must
  // fail every in-flight RPC so its Completer never hangs. The worker now
  // delivers that event atomically with Isolate.exit; here we verify the
  // session reacts to it correctly.
  test('SftpClosedEvent fails in-flight RPCs with a "closed" SftpException',
      () async {
    // Drop every command on the floor: no reply is ever sent, so the only way
    // the Completer can settle is via the close path.
    workerInbox.listen((_) {});
    final pending = session.list('/never-answered');
    fromWorker.sendPort.send(SftpClosedEvent());
    await expectLater(
        pending,
        throwsA(
            isA<SftpException>().having((e) => e.code, 'code', 'closed')));
  });

  test('SftpClosedEvent surfaces SftpStatus.closed on the status stream',
      () async {
    workerInbox.listen((_) {});
    final closedStatus =
        session.status.firstWhere((s) => s == SftpStatus.closed);
    fromWorker.sendPort.send(SftpClosedEvent());
    expect(await closedStatus.timeout(const Duration(seconds: 2)),
        SftpStatus.closed);
  });

  // Reliability finding #1 (leak class): close() must close the broadcast
  // controllers so any retained subscriptions (e.g. connections_view's
  // hostKeyRequests/connectErrors listeners) receive a done signal and don't
  // dangle. We assert the streams complete (onDone fires) after close().
  test('close() drains broadcast streams so subscriptions get a done signal',
      () async {
    workerInbox.listen((_) {});
    final hostKeyDone = Completer<void>();
    final errorsDone = Completer<void>();
    session.hostKeyRequests.listen((_) {}, onDone: hostKeyDone.complete);
    session.connectErrors.listen((_) {}, onDone: errorsDone.complete);

    await session.close();

    await hostKeyDone.future.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('hostKeyRequests stream never closed'));
    await errorsDone.future.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('connectErrors stream never closed'));
  });
}
