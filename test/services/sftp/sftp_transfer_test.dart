// test/services/sftp/sftp_transfer_test.dart
//
// Isolate-free unit tests for the SFTP transfer core (SftpTransferEngine).
// Before the ADR-0014 refactor, doDownload/doUpload lived as closures inside
// the worker isolate entry point and could only be exercised against a real
// server (the skipped sftp_live_test.dart). The engine extracts that core
// verbatim behind two narrow interfaces, so the six critical paths
// (.part→rename atomicity, cancel cleanup, mid-stream error cleanup, for both
// download and upload + overwrite) are now deterministic CI unit tests driven
// by in-memory fakes.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/sftp_transfer.dart';

void main() {
  // ---- happy path: download ----
  test('download writes to .part then renames atomically to the final name',
      () async {
    final remote = FakeRemoteFs();
    final local = FakeLocalFs();
    final events = <SftpEvent>[];
    final engine = SftpTransferEngine(
      remoteFs: remote,
      localFs: local,
      emit: events.add,
    );

    final read = remote.stageRead('/remote/file.bin', total: 6);
    final fut = engine.download(1, '/remote/file.bin', '/local/file.bin');

    await read.subscribed;
    read.emit([1, 2, 3]);
    read.emit([4, 5, 6]);
    read.done();
    await fut;

    // .part was written, then renamed to the final name; no .part remains.
    expect(local.files.containsKey('/local/file.bin.part'), isFalse);
    expect(local.files['/local/file.bin'], [1, 2, 3, 4, 5, 6]);
    expect(local.renames, [('/local/file.bin.part', '/local/file.bin')]);
    expect(local.deletes, isEmpty);
    expect(events.whereType<TransferDone>().map((e) => e.finalPath),
        ['/local/file.bin']);
    expect(events.whereType<TransferProgress>().length, 2);
    expect(events.whereType<TransferFailed>(), isEmpty);
  });

  // ---- cancel: download ----
  test('cancelling a download deletes the .part and never renames', () async {
    final remote = FakeRemoteFs();
    final local = FakeLocalFs();
    final events = <SftpEvent>[];
    final engine = SftpTransferEngine(
      remoteFs: remote,
      localFs: local,
      emit: events.add,
    );

    final read = remote.stageRead('/remote/file.bin', total: 100);
    final fut = engine.download(2, '/remote/file.bin', '/local/file.bin');

    // Let the engine subscribe (open+length are async) before emitting/cancel.
    await read.subscribed;
    read.emit([1, 2, 3]); // partial
    await Future<void>.delayed(Duration.zero); // deliver the chunk
    engine.cancel(2); // user cancels mid-stream
    await fut;

    expect(read.cancelled, isTrue, reason: 'read subscription must be cancelled');
    expect(local.files.containsKey('/local/file.bin'), isFalse);
    expect(local.files.containsKey('/local/file.bin.part'), isFalse,
        reason: '.part must be cleaned up on cancel');
    expect(local.deletes, contains('/local/file.bin.part'));
    expect(local.renames, isEmpty);
    final failed = events.whereType<TransferFailed>().toList();
    expect(failed.single.message, 'İptal edildi');
    expect(events.whereType<TransferDone>(), isEmpty);
  });

  // ---- mid-stream error: download ----
  test('a download stream error cleans up the .part and never renames',
      () async {
    final remote = FakeRemoteFs();
    final local = FakeLocalFs();
    final events = <SftpEvent>[];
    final engine = SftpTransferEngine(
      remoteFs: remote,
      localFs: local,
      emit: events.add,
      mapErr: (e) => 'mapped:$e',
    );

    final read = remote.stageRead('/remote/file.bin', total: 100);
    final fut = engine.download(3, '/remote/file.bin', '/local/file.bin');

    await read.subscribed;
    read.emit([1, 2]);
    read.error('boom'); // network/read failure mid-stream
    await fut;

    expect(local.files.containsKey('/local/file.bin'), isFalse);
    expect(local.files.containsKey('/local/file.bin.part'), isFalse);
    expect(local.deletes, contains('/local/file.bin.part'));
    expect(local.renames, isEmpty);
    final failed = events.whereType<TransferFailed>().toList();
    expect(failed.single.message, 'mapped:boom');
    expect(events.whereType<TransferDone>(), isEmpty);
  });

  // ---- happy path: upload ----
  test('upload writes to remote .part then renames to the final name',
      () async {
    final remote = FakeRemoteFs();
    final local = FakeLocalFs();
    final events = <SftpEvent>[];
    final engine = SftpTransferEngine(
      remoteFs: remote,
      localFs: local,
      emit: events.add,
    );
    local.files['/local/up.bin'] = [9, 8, 7];

    await engine.upload(4, '/local/up.bin', '/remote/up.bin');

    expect(remote.files.containsKey('/remote/up.bin.part'), isFalse);
    expect(remote.files['/remote/up.bin'], [9, 8, 7]);
    expect(remote.renames, [('/remote/up.bin.part', '/remote/up.bin')]);
    expect(remote.removes, isEmpty);
    expect(events.whereType<TransferDone>().map((e) => e.finalPath),
        ['/remote/up.bin']);
    expect(events.whereType<TransferFailed>(), isEmpty);
  });

  // ---- cancel: upload ----
  test('cancelling an upload aborts the writer, removes the .part, no rename',
      () async {
    final remote = FakeRemoteFs();
    final local = FakeLocalFs();
    final events = <SftpEvent>[];
    final engine = SftpTransferEngine(
      remoteFs: remote,
      localFs: local,
      emit: events.add,
    );
    local.files['/local/up.bin'] = [1, 2, 3, 4];
    remote.holdWriteDone('/remote/up.bin.part'); // writer.done won't complete on its own

    final fut = engine.upload(5, '/local/up.bin', '/remote/up.bin');
    await Future<void>.delayed(Duration.zero); // let write() start
    engine.cancel(5);
    await fut;

    final handle = remote.writeHandles['/remote/up.bin.part']!;
    expect(handle.aborted, isTrue, reason: 'writer.abort() must be called');
    expect(remote.files.containsKey('/remote/up.bin'), isFalse);
    expect(remote.removes, contains('/remote/up.bin.part'));
    expect(remote.renames, isEmpty);
    final failed = events.whereType<TransferFailed>().toList();
    expect(failed.single.message, 'İptal edildi');
    expect(events.whereType<TransferDone>(), isEmpty);
  });

  // ---- atomicity / overwrite ----
  test('download over an existing final name overwrites via the rename only',
      () async {
    final remote = FakeRemoteFs();
    final local = FakeLocalFs();
    final events = <SftpEvent>[];
    final engine = SftpTransferEngine(
      remoteFs: remote,
      localFs: local,
      emit: events.add,
    );
    // A stale final file already exists; the half-written .part must never
    // appear under the final name until the final rename overwrites it.
    local.files['/local/file.bin'] = [0, 0, 0];

    final read = remote.stageRead('/remote/file.bin', total: 4);
    final fut = engine.download(6, '/remote/file.bin', '/local/file.bin');

    await read.subscribed;
    read.emit([7, 7]);
    await Future<void>.delayed(Duration.zero); // chunk written to .part
    // Mid-transfer the final name still holds the OLD bytes; the half-written
    // .part has NOT clobbered it.
    expect(local.files['/local/file.bin'], [0, 0, 0]);
    expect(local.files['/local/file.bin.part'], [7, 7]);
    read.emit([7, 7]);
    read.done();
    await fut;

    // The rename overwrote the final name with the freshly downloaded bytes.
    expect(local.files['/local/file.bin'], [7, 7, 7, 7]);
    expect(local.files.containsKey('/local/file.bin.part'), isFalse);
    expect(local.renames, [('/local/file.bin.part', '/local/file.bin')]);
    expect(events.whereType<TransferDone>().single.finalPath,
        '/local/file.bin');
  });
}

// ---------------------------------------------------------------------------
// In-memory fakes.
// ---------------------------------------------------------------------------

class FakeRemoteFs implements RemoteFs {
  final Map<String, List<int>> files = {};
  final List<(String, String)> renames = [];
  final List<String> removes = [];
  final Map<String, StagedRead> _reads = {};
  final Map<String, FakeRemoteWriteHandle> writeHandles = {};
  final Set<String> _heldWriteDone = {};

  StagedRead stageRead(String path, {int? total}) {
    final r = StagedRead(total);
    _reads[path] = r;
    return r;
  }

  /// Make the writer for [path] not auto-complete its `writeDone` (so a test
  /// can cancel before it finishes).
  void holdWriteDone(String path) => _heldWriteDone.add(path);

  @override
  Future<RemoteReadHandle> openRead(String path) async {
    final r = _reads[path];
    if (r == null) throw StateError('no staged read for $path');
    return _FakeRemoteReadHandle(r);
  }

  @override
  Future<RemoteWriteHandle> openWrite(String path) async {
    final h = FakeRemoteWriteHandle(
        path, files, hold: _heldWriteDone.contains(path));
    writeHandles[path] = h;
    return h;
  }

  @override
  Future<void> remove(String path) async {
    removes.add(path);
    files.remove(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    renames.add((from, to));
    final bytes = files.remove(from);
    if (bytes != null) files[to] = bytes;
  }
}

class StagedRead {
  StagedRead(this.total);
  final int? total;
  final controller = StreamController<List<int>>();
  final _subscribed = Completer<void>();
  bool cancelled = false;

  /// Completes once the engine has subscribed to the read stream (i.e. after
  /// the async open+length steps), so tests can emit/cancel deterministically.
  Future<void> get subscribed => _subscribed.future;
  void markSubscribed() {
    if (!_subscribed.isCompleted) _subscribed.complete();
  }

  void emit(List<int> chunk) => controller.add(chunk);
  void error(Object e) => controller.addError(e);
  void done() => controller.close();
}

class _FakeRemoteReadHandle implements RemoteReadHandle {
  _FakeRemoteReadHandle(this._read);
  final StagedRead _read;

  @override
  Future<int?> length() async => _read.total;

  @override
  Stream<List<int>> read() {
    _read.controller.onListen = () => _read.markSubscribed();
    _read.controller.onCancel = () => _read.cancelled = true;
    return _read.controller.stream;
  }

  @override
  Future<void> close() async {}
}

class FakeRemoteWriteHandle implements RemoteWriteHandle {
  FakeRemoteWriteHandle(this.path, this._files, {required this.hold});
  final String path;
  final Map<String, List<int>> _files;
  final bool hold;
  final _doneCompleter = Completer<void>();
  bool aborted = false;

  @override
  void write(Stream<Uint8List> data,
      {required void Function(int) onProgress}) {
    final buf = <int>[];
    data.listen(
      (chunk) {
        buf.addAll(chunk);
        onProgress(buf.length);
      },
      onDone: () {
        _files[path] = buf;
        if (!hold && !_doneCompleter.isCompleted) _doneCompleter.complete();
      },
      onError: (Object e) {
        if (!_doneCompleter.isCompleted) _doneCompleter.completeError(e);
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> get writeDone => _doneCompleter.future;

  @override
  void abortWrite() {
    aborted = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  Future<void> close() async {}
}

class FakeLocalFs implements LocalFs {
  final Map<String, List<int>> files = {};
  final List<(String, String)> renames = [];
  final List<String> deletes = [];

  @override
  LocalSink openWrite(String path) {
    files[path] = <int>[]; // a fresh empty .part
    return _FakeLocalSink(path, files);
  }

  @override
  Future<int?> length(String path) async => files[path]?.length;

  @override
  Future<void> delete(String path) async {
    deletes.add(path);
    if (!files.containsKey(path)) throw StateError('no such file: $path');
    files.remove(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    renames.add((from, to));
    final bytes = files.remove(from);
    if (bytes == null) throw StateError('no such file: $from');
    files[to] = bytes;
  }

  @override
  Stream<List<int>> openRead(String path) {
    final bytes = files[path];
    if (bytes == null) return Stream.error(StateError('no such file: $path'));
    return Stream.value(List<int>.from(bytes));
  }
}

class _FakeLocalSink implements LocalSink {
  _FakeLocalSink(this.path, this._files);
  final String path;
  final Map<String, List<int>> _files;

  @override
  void add(List<int> data) => _files[path]!.addAll(data);

  @override
  Future<void> close() async {}
}
