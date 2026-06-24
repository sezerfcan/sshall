import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';

void main() {
  test('execCommand defaults to null (plain shell)', () {
    const p = SshConnectParams(host: 'h', port: 22, username: 'u');
    expect(p.execCommand, isNull);
  });

  test('execCommand carries the docker exec invocation', () {
    const p = SshConnectParams(
      host: 'h',
      port: 22,
      username: 'u',
      execCommand: 'docker exec -it api sh',
    );
    expect(p.execCommand, 'docker exec -it api sh');
  });
}
