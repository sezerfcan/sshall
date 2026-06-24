import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'sftp_transfer.dart';

/// Production [RemoteFs] adapter backed by dartssh2's [SftpClient].
///
/// Thin and logic-free: it only forwards to `SftpClient`/`SftpFile`. The
/// transfer policy (`.part`→rename, cancel, cleanup) lives in
/// [SftpTransferEngine], which is unit-tested with fakes (ADR 0014).
class DartSftpRemoteFs implements RemoteFs {
  DartSftpRemoteFs(this._sftp);

  final SftpClient _sftp;

  @override
  Future<RemoteReadHandle> openRead(String path) async {
    final file = await _sftp.open(path);
    return _DartRemoteReadHandle(file);
  }

  @override
  Future<RemoteWriteHandle> openWrite(String path) async {
    final file = await _sftp.open(path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate);
    return _DartRemoteWriteHandle(file);
  }

  @override
  Future<void> remove(String path) => _sftp.remove(path);

  @override
  Future<void> rename(String from, String to) => _sftp.rename(from, to);
}

class _DartRemoteReadHandle implements RemoteReadHandle {
  _DartRemoteReadHandle(this._file);

  final SftpFile _file;

  @override
  Future<int?> length() async => (await _file.stat()).size;

  @override
  Stream<List<int>> read() => _file.read();

  @override
  Future<void> close() => _file.close();
}

class _DartRemoteWriteHandle implements RemoteWriteHandle {
  _DartRemoteWriteHandle(this._file);

  final SftpFile _file;
  SftpFileWriter? _writer;

  @override
  void write(Stream<Uint8List> data,
      {required void Function(int) onProgress}) {
    _writer = _file.write(data, onProgress: onProgress);
  }

  @override
  Future<void> get writeDone => _writer!.done;

  @override
  void abortWrite() => _writer?.abort();

  @override
  Future<void> close() => _file.close();
}

/// Production [LocalFs] adapter backed by `dart:io File`.
class DartLocalFs implements LocalFs {
  const DartLocalFs();

  @override
  LocalSink openWrite(String path) => _DartLocalSink(File(path).openWrite());

  @override
  Future<int?> length(String path) => File(path).length();

  @override
  Future<void> delete(String path) async {
    await File(path).delete();
  }

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();
}

class _DartLocalSink implements LocalSink {
  _DartLocalSink(this._sink);

  final IOSink _sink;

  @override
  void add(List<int> data) => _sink.add(data);

  @override
  Future<void> close() => _sink.close();
}
