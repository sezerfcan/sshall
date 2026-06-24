import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/sftp_service.dart';

void main() {
  test('connect to a closed port surfaces a network SftpConnectError',
      () async {
    final session = await SftpService().connect(const SshConnectParams(
      host: '127.0.0.1',
      port: 47593, // almost certainly closed -> fast refusal
      username: 'nobody',
      password: 'x',
    ));
    final err = await session.connectErrors.first
        .timeout(const Duration(seconds: 15));
    expect(err.code, 'network');
    await session.close();
  });
}
