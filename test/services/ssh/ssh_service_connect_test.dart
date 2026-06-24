import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';

void main() {
  test('connect completes the isolate handshake and forwards a worker event',
      () async {
    // Port 47591 on localhost is almost certainly closed -> fast "refused",
    // which the worker reports as a network ErrorEvent. This proves the
    // spawn -> SendPort handshake -> ConnectCommand -> event-forwarding path
    // works, without needing a live SSH server.
    final session = await SshService().connect(const SshConnectParams(
      host: '127.0.0.1',
      port: 47591,
      username: 'nobody',
      password: 'x',
    ));
    final err = await session.events
        .firstWhere((e) => e is ErrorEvent)
        .timeout(const Duration(seconds: 15)) as ErrorEvent;
    expect(err.code, 'network');
    await session.close();
  });
}
