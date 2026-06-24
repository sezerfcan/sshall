import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/sftp_service.dart';
import 'package:sshall/services/sftp/remote_file_ops.dart';

void main() {
  test('SftpSession satisfies RemoteFileOps (static upcast compiles)', () {
    // The real assertion is static: an SftpSession is assignable to
    // RemoteFileOps. If SftpSession did not implement the interface this
    // function body would not compile.
    RemoteFileOps up(SftpSession s) => s;
    expect(up, isNotNull);
  });
}
