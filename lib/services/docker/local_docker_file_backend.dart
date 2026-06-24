import 'dart:async';
import 'dart:io';

import '../../data/models/remote_entry.dart';
import '../sftp/remote_file_ops.dart';
import '../sftp/sftp_messages.dart';
import '../sftp/sftp_service.dart' show SftpException;
import 'ls_parse.dart';

/// Runs a process and returns its result. Defaults to [Process.run]; injected in
/// tests. (Local Docker mirror of v1's SSH `CommandRunner` seam.)
typedef ProcessRunner = Future<ProcessResult> Function(
    String exe, List<String> args);

/// [RemoteFileOps] over a LOCAL container via `docker exec` (metadata, parsed by
/// [parseLsLa]) + `docker cp` (transfer straight to/from the local filesystem —
/// the daemon is local, so no tar streaming). Commands are passed as an argument
/// LIST (no shell), so there is no quoting/injection surface. See ADR 0028.
class LocalDockerFileBackend implements RemoteFileOps {
  LocalDockerFileBackend(this._bin, this._id, {ProcessRunner? runner})
      : _run = runner ?? Process.run;

  final String _bin;
  final String _id;
  final ProcessRunner _run;
  int _nextTransferId = 1;
  final StreamController<SftpEvent> _transfers =
      StreamController<SftpEvent>.broadcast();

  Future<ProcessResult> _exec(List<String> cmd) =>
      _run(_bin, ['exec', _id, ...cmd]);

  String _err(ProcessResult r) => (r.stderr as String? ?? '').trim();

  Future<void> _execOk(List<String> cmd) async {
    final r = await _exec(cmd);
    if (r.exitCode != 0) throw SftpException('op', _err(r));
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final r = await _exec(['ls', '-la', path]);
    if (r.exitCode != 0) throw SftpException('op', _err(r));
    return parseLsLa(path, r.stdout as String? ?? '');
  }

  @override
  Future<RemoteEntry?> stat(String path) async {
    final r = await _exec(['ls', '-lad', path]);
    if (r.exitCode != 0) return null;
    final entries = parseLsLa(_parent(path), r.stdout as String? ?? '');
    return entries.isEmpty ? null : entries.first;
  }

  @override
  Future<void> mkdir(String path) => _execOk(['mkdir', '-p', path]);

  @override
  Future<void> rename(String from, String to) => _execOk(['mv', from, to]);

  @override
  Future<void> remove(String path, {required bool isDir}) =>
      _execOk(['rm', isDir ? '-rf' : '-f', path]);

  @override
  Future<void> chmod(String path, int mode) =>
      _execOk(['chmod', mode.toRadixString(8).padLeft(3, '0'), path]);

  @override
  int startDownload(String remotePath, String localFinalPath) {
    final id = _nextTransferId++;
    unawaited(
        _cp(['cp', '$_id:$remotePath', localFinalPath], id, localFinalPath));
    return id;
  }

  @override
  int startUpload(String localPath, String remoteFinalPath) {
    final id = _nextTransferId++;
    unawaited(
        _cp(['cp', localPath, '$_id:$remoteFinalPath'], id, remoteFinalPath));
    return id;
  }

  Future<void> _cp(List<String> args, int id, String finalPath) async {
    try {
      final r = await _run(_bin, args);
      if (r.exitCode != 0) {
        _emit(TransferFailed(id, _err(r)));
        return;
      }
      _emit(TransferProgress(id, 1, 1));
      _emit(TransferDone(id, finalPath));
    } catch (e) {
      _emit(TransferFailed(id, e.toString()));
    }
  }

  void _emit(SftpEvent e) {
    if (!_transfers.isClosed) _transfers.add(e);
  }

  @override
  void cancel(int transferId) {} // v1: docker cp transfers are short; best-effort

  @override
  Stream<SftpEvent> get transfers => _transfers.stream;

  @override
  Future<void> close() async {
    await _transfers.close();
  }

  static String _parent(String p) {
    final i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }
}
