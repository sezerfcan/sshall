import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/remote_edit_session.dart';

void main() {
  RemoteEditSession base() => const RemoteEditSession(
        id: 'e1',
        remotePath: '/srv/app.conf',
        localTempPath: '/tmp/e1/app.conf',
        baseMtimeMs: 1000,
        baseSize: 42,
        mode: 420, // 0644
        lastLocalMtimeMs: 1000,
        lastLocalSize: 42,
        status: RemoteEditStatus.watching,
        message: null,
      );

  test('copyWith changes only named fields', () {
    final s = base().copyWith(status: RemoteEditStatus.uploading);
    expect(s.status, RemoteEditStatus.uploading);
    expect(s.remotePath, '/srv/app.conf');
    expect(s.baseSize, 42);
    expect(s.baseMtimeMs, 1000); // untouched nullable field preserved
    expect(s.mode, 420);
    expect(s.message, isNull);
  });

  test('copyWith can refresh base + lastLocal together', () {
    final s = base().copyWith(
      baseMtimeMs: 2000,
      baseSize: 50,
      lastLocalMtimeMs: 2000,
      lastLocalSize: 50,
      status: RemoteEditStatus.watching,
      message: 'x',
    );
    expect(s.baseMtimeMs, 2000);
    expect(s.lastLocalSize, 50);
    expect(s.message, 'x');
  });
}
