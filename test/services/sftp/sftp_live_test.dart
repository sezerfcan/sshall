// test/services/sftp/sftp_live_test.dart
//
// Live SFTP roundtrip against a real server. Skipped unless SSHALL_LIVE is set,
// so CI stays green without a server. To run locally against the PoC server:
//   SSHALL_LIVE=1 SFTP_HOST=127.0.0.1 SFTP_PORT=2222 SFTP_USER=poc \
//   SFTP_PASS=poc flutter test test/services/sftp/sftp_live_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/remote_path.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/sftp_service.dart';

void main() {
  final live = Platform.environment['SSHALL_LIVE'] == '1';

  /// Connects an [SftpSession] to the PoC server (host/port/credentials from
  /// env, with the same defaults the existing live test uses) and waits until
  /// it reports [SftpStatus.ready], auto-accepting the host key on first use.
  Future<SftpSession> connectLive() async {
    final env = Platform.environment;
    final session = await SftpService().connect(SshConnectParams(
      host: env['SFTP_HOST'] ?? '127.0.0.1',
      port: int.parse(env['SFTP_PORT'] ?? '2222'),
      username: env['SFTP_USER'] ?? 'poc',
      password: env['SFTP_PASS'] ?? 'poc',
    ));
    // Accept host key on first use.
    session.hostKeyRequests.listen((_) => session.decideHostKey(true));
    await session.status
        .firstWhere((s) => s == SftpStatus.ready)
        .timeout(const Duration(seconds: 20));
    return session;
  }

  /// Awaits the [TransferDone] event for [transferId] on the [transfers]
  /// stream, bounded by a timeout so a stalled transfer fails fast.
  Future<TransferDone> awaitDone(SftpSession session, int transferId) =>
      session.transfers
          .firstWhere((e) => e is TransferDone && e.transferId == transferId)
          .timeout(const Duration(seconds: 20))
          .then((e) => e as TransferDone);

  test('upload then download yields byte-identical content', () async {
    final session = await connectLive();

    final tmp = await Directory.systemTemp.createTemp('sftp_live');
    final src = File('${tmp.path}/src.bin');
    final payload = Uint8List.fromList(List.generate(4096, (i) => i % 256));
    await src.writeAsBytes(payload);

    // upload
    final upId = session.startUpload(src.path, 'sftp_live_upload.bin');
    await awaitDone(session, upId);

    // download back
    final dst = '${tmp.path}/dst.bin';
    final dlId = session.startDownload('sftp_live_upload.bin', dst);
    await awaitDone(session, dlId);

    expect(await File(dst).readAsBytes(), payload);

    await session.remove('sftp_live_upload.bin', isDir: false);
    await session.close();
    await tmp.delete(recursive: true);
  }, skip: live ? false : 'set SSHALL_LIVE=1 to run live SFTP test');

  test('recursive: upload a nested dir, download it back, byte-equal',
      () async {
    final session = await connectLive();

    // 1. Build a local source tree:
    //      docs/a.txt       -> "A"
    //      docs/sub/b.txt   -> "B"
    final srcTmp = await Directory.systemTemp.createTemp('sftp_live_rec_src');
    final dstTmp = await Directory.systemTemp.createTemp('sftp_live_rec_dst');
    final docsDir = Directory('${srcTmp.path}/docs');
    final subDir = Directory('${docsDir.path}/sub');
    await subDir.create(recursive: true);
    final localA = File('${docsDir.path}/a.txt');
    final localB = File('${subDir.path}/b.txt');
    await localA.writeAsString('A');
    await localB.writeAsString('B');

    // A fresh remote root for this run so the test is self-contained and the
    // structure assertions below are deterministic.
    final remoteRoot = 'sftp_live_rec_${DateTime.now().microsecondsSinceEpoch}';
    final remoteDocs = RemotePath.join(remoteRoot, 'docs');
    final remoteSub = RemotePath.join(remoteDocs, 'sub');
    final remoteA = RemotePath.join(remoteDocs, 'a.txt');
    final remoteB = RemotePath.join(remoteSub, 'b.txt');

    try {
      // 2. Upload the tree. Drive it the way the view does: create each dir
      //    shallow -> deep, then upload each file to its final remote path.
      for (final dir in [remoteRoot, remoteDocs, remoteSub]) {
        await session.mkdir(dir).timeout(const Duration(seconds: 20));
      }
      final upA = session.startUpload(localA.path, remoteA);
      await awaitDone(session, upA);
      final upB = session.startUpload(localB.path, remoteB);
      await awaitDone(session, upB);

      // 3. List the remote tree and assert the structure mirrors the source.
      final rootEntries =
          await session.list(remoteRoot).timeout(const Duration(seconds: 20));
      expect(
        rootEntries.where((e) => e.name == 'docs' && e.isDir),
        isNotEmpty,
        reason: 'remote docs/ dir should exist',
      );
      final docsEntries =
          await session.list(remoteDocs).timeout(const Duration(seconds: 20));
      expect(
        docsEntries.where((e) => e.name == 'sub' && e.isDir),
        isNotEmpty,
        reason: 'remote docs/sub dir should exist',
      );
      expect(
        docsEntries.where((e) => e.name == 'a.txt' && !e.isDir),
        isNotEmpty,
        reason: 'remote docs/a.txt should exist',
      );
      final subEntries =
          await session.list(remoteSub).timeout(const Duration(seconds: 20));
      expect(
        subEntries.where((e) => e.name == 'b.txt' && !e.isDir),
        isNotEmpty,
        reason: 'remote docs/sub/b.txt should exist',
      );

      // 4. Download the tree back into a second temp dir and assert each file
      //    is byte-for-byte identical to the source (the integrity oracle).
      final dlDocs = Directory('${dstTmp.path}/docs');
      final dlSub = Directory('${dlDocs.path}/sub');
      await dlSub.create(recursive: true);
      final dlAPath = '${dlDocs.path}/a.txt';
      final dlBPath = '${dlSub.path}/b.txt';

      final dlA = session.startDownload(remoteA, dlAPath);
      await awaitDone(session, dlA);
      final dlB = session.startDownload(remoteB, dlBPath);
      await awaitDone(session, dlB);

      expect(await File(dlAPath).readAsBytes(), await localA.readAsBytes());
      expect(await File(dlBPath).readAsBytes(), await localB.readAsBytes());
    } finally {
      // 5. Clean up remote tree (deepest -> shallowest) and local temp dirs.
      await session.remove(remoteB, isDir: false).catchError((_) {});
      await session.remove(remoteA, isDir: false).catchError((_) {});
      await session.remove(remoteSub, isDir: true).catchError((_) {});
      await session.remove(remoteDocs, isDir: true).catchError((_) {});
      await session.remove(remoteRoot, isDir: true).catchError((_) {});
      await session.close();
      await srcTmp.delete(recursive: true);
      await dstTmp.delete(recursive: true);
    }
  }, skip: live ? false : 'set SSHALL_LIVE=1 to run live SFTP test');
}
