import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/services/ssh/terminal_session.dart';

void main() {
  test('SshSession is a TerminalSession', () {
    final s = SshSession.test();
    expect(s, isA<TerminalSession>());
  });
}
