import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/remote_entry.dart';
import 'package:sshall/features/sftp/edit_poller.dart';
import 'package:sshall/features/sftp/file_opener.dart';
import 'package:sshall/features/sftp/local_file_probe.dart';
import 'package:sshall/features/sftp/remote_edit_controller.dart';
import 'package:sshall/features/sftp/remote_edit_session.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';

class FakeOpener implements FileOpener {
  final List<String> opened = [];
  bool result = true;
  @override
  Future<bool> open(String path) async {
    opened.add(path);
    return result;
  }
}

class FakePoller implements EditPoller {
  void Function()? onTick;
  bool running = false;
  @override
  void start(Duration interval, void Function() cb) {
    onTick = cb;
    running = true;
  }
  @override
  void stop() => running = false;
  void tick() => onTick?.call();
}

/// In-memory probe: tests script stats per path.
class FakeProbe implements LocalFileProbe {
  final Map<String, ({int mtimeMs, int size})> stats = {};
  final List<String> ensured = [];
  final List<String> deleted = [];
  List<String> children = [];
  @override
  Future<({int mtimeMs, int size})?> stat(String path) async => stats[path];
  @override
  Future<void> ensureDir(String dirPath) async => ensured.add(dirPath);
  @override
  Future<void> deleteDir(String dirPath) async => deleted.add(dirPath);
  @override
  Future<List<String>> childDirs(String rootPath) async => children;
}

RemoteEntry remoteFile({
  String path = '/srv/app.conf',
  int? mtime = 1000,
  int size = 42,
  int? mode = 420,
}) => RemoteEntry(
      name: path.split('/').last,
      path: path,
      isDir: false,
      isSymlink: false,
      size: size,
      modified: mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime),
      mode: mode,
    );

/// Records calls + lets the test drive returns/ids.
class Harness {
  final downloads = <(String, String)>[];
  final uploads = <(String, String)>[];
  final chmods = <(String, int)>[];
  int _tid = 100;
  int nextDownloadId = 0, nextUploadId = 0;
  RemoteEntry? statResult = remoteFile();

  final opener = FakeOpener();
  final poller = FakePoller();
  final probe = FakeProbe();
  int onChangedCount = 0;
  int _idSeq = 0;

  late final RemoteEditController c = RemoteEditController(
    startDownload: (r, l) {
      downloads.add((r, l));
      return nextDownloadId = ++_tid;
    },
    startUpload: (l, r) {
      uploads.add((l, r));
      return nextUploadId = ++_tid;
    },
    stat: (r) async => statResult,
    chmod: (r, m) async => chmods.add((r, m)),
    fileOpener: opener,
    poller: poller,
    probe: probe,
    tempRootPath: () async => '/tmp/remote-edits',
    onChanged: () => onChangedCount++,
    newId: () => 'e${++_idSeq}',
    pollInterval: const Duration(seconds: 1),
  );
}

void main() {
  test('startEdit downloads to temp, then on done opens + watches', () async {
    final h = Harness();
    h.statResult = remoteFile(mtime: 1000, size: 42, mode: 420);
    await h.c.startEdit(remoteFile());

    // session created in downloading state; download issued to a temp path
    expect(h.c.sessions, hasLength(1));
    expect(h.c.sessions.single.status, RemoteEditStatus.downloading);
    expect(h.probe.ensured, hasLength(1)); // session temp dir created
    expect(h.downloads, hasLength(1));
    final tempPath = h.downloads.single.$2;
    expect(tempPath, contains('e1'));
    expect(tempPath, endsWith('app.conf'));

    // post-download local baseline exists
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);

    expect(h.opener.opened, [tempPath]);
    final s = h.c.sessions.single;
    expect(s.status, RemoteEditStatus.watching);
    expect(s.baseMtimeMs, 1000);
    expect(s.baseSize, 42);
    expect(s.mode, 420);
    expect(s.lastLocalMtimeMs, 5000); // baseline captured after download
    expect(h.poller.running, isTrue);
  });

  test('download failure → error status, no open', () async {
    final h = Harness();
    await h.c.startEdit(remoteFile());
    h.c.onTransferEvent(TransferFailed(h.nextDownloadId, 'net'));
    await Future<void>.delayed(Duration.zero);
    expect(h.c.sessions.single.status, RemoteEditStatus.error);
    expect(h.opener.opened, isEmpty);
  });

  test('open failure (no default app) → error status', () async {
    final h = Harness();
    h.opener.result = false;
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);
    expect(h.c.sessions.single.status, RemoteEditStatus.error);
  });

  test('local save with unchanged remote → upload + chmod + base refresh', () async {
    final h = Harness();
    h.statResult = remoteFile(mtime: 1000, size: 42, mode: 420);
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);

    // user saves: temp grows
    h.probe.stats[tempPath] = (mtimeMs: 6000, size: 50);
    h.poller.tick();
    await Future<void>.delayed(Duration.zero);

    // remote still matches base (statResult unchanged) → upload issued
    expect(h.uploads, hasLength(1));
    expect(h.uploads.single, (tempPath, '/srv/app.conf'));

    // remote now reports the new state after our write
    h.statResult = remoteFile(mtime: 7000, size: 50, mode: 420);
    h.c.onTransferEvent(TransferDone(h.nextUploadId, '/srv/app.conf'));
    await Future<void>.delayed(Duration.zero);

    expect(h.chmods, [('/srv/app.conf', 420)]); // original mode preserved
    final s = h.c.sessions.single;
    expect(s.status, RemoteEditStatus.watching);
    expect(s.baseMtimeMs, 7000); // base advanced to post-upload remote
    expect(s.baseSize, 50);
    expect(s.lastLocalMtimeMs, 6000); // won't re-fire for same local stat
  });

  test('no upload when local unchanged on tick', () async {
    final h = Harness();
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);
    h.poller.tick(); // same stat
    await Future<void>.delayed(Duration.zero);
    expect(h.uploads, isEmpty);
  });

  Future<Harness> watchingWithLocalChange() async {
    final h = Harness();
    h.statResult = remoteFile(mtime: 1000, size: 42, mode: 420);
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);
    // remote drifted since download
    h.statResult = remoteFile(mtime: 9999, size: 99, mode: 420);
    // local save
    h.probe.stats[tempPath] = (mtimeMs: 6000, size: 50);
    h.poller.tick();
    await Future<void>.delayed(Duration.zero);
    return h;
  }

  test('remote changed under us → conflict, no upload', () async {
    final h = await watchingWithLocalChange();
    expect(h.uploads, isEmpty);
    expect(h.c.sessions.single.status, RemoteEditStatus.conflict);
  });

  test('resolveConflict.overwriteRemote forces the upload', () async {
    final h = await watchingWithLocalChange();
    await h.c.resolveConflict(h.c.sessions.single.id, ConflictChoice.overwriteRemote);
    await Future<void>.delayed(Duration.zero);
    expect(h.uploads, hasLength(1));
    expect(h.c.sessions.single.status, RemoteEditStatus.uploading);
  });

  test('resolveConflict.keepEditing returns to watching, no upload', () async {
    final h = await watchingWithLocalChange();
    await h.c.resolveConflict(h.c.sessions.single.id, ConflictChoice.keepEditing);
    expect(h.uploads, isEmpty);
    expect(h.c.sessions.single.status, RemoteEditStatus.watching);
    expect(h.poller.running, isTrue); // session back to watching → poller keeps running
  });

  test('resolveConflict.saveAsLocal stops session, keeps temp', () async {
    final h = await watchingWithLocalChange();
    await h.c.resolveConflict(h.c.sessions.single.id, ConflictChoice.saveAsLocal);
    expect(h.uploads, isEmpty);
    expect(h.probe.deleted, isEmpty); // temp preserved for the user
    expect(h.c.sessions.single.status, RemoteEditStatus.closedRemote);
    expect(h.poller.running, isFalse); // no watching sessions → poller stopped
    expect(h.c.sessions.single.message, contains('Yerel kopya korundu'));
  });

  test('resolveConflict is a no-op when session is not in conflict', () async {
    final h = Harness();
    h.statResult = remoteFile(mtime: 1000, size: 42, mode: 420);
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);

    // session is in `watching` state — resolveConflict must be a no-op
    expect(h.c.sessions.single.status, RemoteEditStatus.watching);
    await h.c.resolveConflict(h.c.sessions.single.id, ConflictChoice.overwriteRemote);
    expect(h.uploads, isEmpty);
    expect(h.c.sessions.single.status, RemoteEditStatus.watching);
  });

  test('finish stops watching, deletes temp dir, removes session', () async {
    final h = Harness();
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);

    final id = h.c.sessions.single.id;
    await h.c.finish(id);
    expect(h.c.sessions, isEmpty);
    expect(h.probe.deleted, hasLength(1)); // session dir removed
    expect(h.poller.running, isFalse); // nothing left to watch
  });

  test('onSftpClosed marks all closedRemote, keeps temp, stops poller', () async {
    final h = Harness();
    await h.c.startEdit(remoteFile());
    final tempPath = h.downloads.single.$2;
    h.probe.stats[tempPath] = (mtimeMs: 5000, size: 42);
    h.c.onTransferEvent(TransferDone(h.nextDownloadId, tempPath));
    await Future<void>.delayed(Duration.zero);

    h.c.onSftpClosed();
    expect(h.c.sessions.single.status, RemoteEditStatus.closedRemote);
    expect(h.probe.deleted, isEmpty);
    expect(h.poller.running, isFalse);
  });

  test('sweepStaleTempDirs deletes orphan dirs when no active sessions', () async {
    final h = Harness();
    h.probe.children = ['/tmp/remote-edits/old1', '/tmp/remote-edits/old2'];
    await h.c.sweepStaleTempDirs();
    expect(h.probe.deleted, containsAll(['/tmp/remote-edits/old1', '/tmp/remote-edits/old2']));
  });

  test('sweepStaleTempDirs is a no-op while a session is active', () async {
    final h = Harness();
    await h.c.startEdit(remoteFile());
    h.probe.children = ['/tmp/remote-edits/old1'];
    await h.c.sweepStaleTempDirs();
    expect(h.probe.deleted, isEmpty); // never delete with live sessions
  });
}
