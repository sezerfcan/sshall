@Tags(['live'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';

// Requires the PoC docker server at 127.0.0.1:2222 (poc/pocpass).
// Run explicitly: flutter test --tags live test/services/ssh/ssh_service_test.dart
void main() {
  test('connects, accepts host key, reaches ready', () async {
    final session = await SshService().connect(const SshConnectParams(
      host: '127.0.0.1',
      port: 2222,
      username: 'poc',
      password: 'pocpass',
    ));
    var ready = false;
    final done = Completer<void>();
    session.events.listen((e) {
      if (e is HostKeyRequestEvent) session.decideHostKey(true);
      if (e is StatusEvent && e.status == SshStatus.ready) {
        ready = true;
        done.complete();
      }
      if (e is ErrorEvent && !done.isCompleted) done.completeError(e.message);
    });
    await done.future.timeout(const Duration(seconds: 20));
    expect(ready, isTrue);
    await session.close();
  }, tags: ['live']);
}
