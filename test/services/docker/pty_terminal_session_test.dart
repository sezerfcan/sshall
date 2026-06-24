import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/pty_terminal_session.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/terminal_session.dart';

void main() {
  test('is a TerminalSession and emits ready + output, buffers backlog', () async {
    final out = StreamController<Uint8List>();
    final exit = Completer<int>();
    final writes = <Uint8List>[];
    final s = PtyTerminalSession.test(
      output: out.stream,
      onWrite: writes.add,
      exitCode: exit.future,
    );
    expect(s, isA<TerminalSession>());

    final events = <WorkerEvent>[];
    s.events.listen(events.add);

    out.add(Uint8List.fromList([104, 105])); // "hi"
    await Future<void>.delayed(Duration.zero);

    // ready status emitted on construction; output forwarded.
    expect(s.currentLifecycle, isA<StatusEvent>());
    expect(events.whereType<OutputEvent>().length, 1);

    // backlog captured the pre-consume output.
    final backlog = s.takeOutputBacklog();
    expect(backlog, [104, 105]);

    s.sendInput(Uint8List.fromList([1, 2]));
    expect(writes.single, [1, 2]);

    exit.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<ClosedEvent>().length, 1);

    await out.close();
    await s.close();
  });
}
