import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../data/models/remote_entry.dart';
import '../sftp/remote_file_ops.dart';
import '../sftp/sftp_messages.dart';
import '../sftp/sftp_service.dart' show SftpException;
import 'docker_file_worker.dart';
import 'ls_parse.dart';
import 'shell_quote.dart';
import 'ssh_docker_host.dart' show CommandResult, CommandRunner;

/// [RemoteFileOps] over a container via `docker exec` (metadata) + `docker cp`
/// tar-stream (transfer). See ADR 0028.
///
/// Two I/O paths:
///  - **Metadata** (`list`/`stat`/`mkdir`/`rename`/`remove`/`chmod`) go through
///    [_runner]. The default runner reuses a single lazily-opened [SSHClient]
///    across calls (so folder browsing does not pay a full SSH handshake per
///    listing). Tests inject a fake [CommandRunner], which bypasses the client
///    entirely — keeping metadata ops synchronously unit-testable.
///  - **Transfers** (`startDownload`/`startUpload`) delegate to
///    docker_file_worker.dart. Each transfer opens its own dedicated SSH client
///    (long-lived byte streams must not contend with metadata browsing) and
///    emits the existing [SftpEvent] transfer types on [transfers], so the
///    existing TransferQueue consumes them unchanged.
class DockerFileBackend implements RemoteFileOps {
  DockerFileBackend(
    this._base,
    this._containerId, {
    String binary = 'docker',
    CommandRunner? commandRunner,
  })  : _bin = binary,
        _injectedRunner = commandRunner;

  final SshConnectParams _base;
  final String _containerId;
  final String _bin;

  /// Injected by tests; when null the shared-client runner is used.
  final CommandRunner? _injectedRunner;

  /// Lazily opened, reused across metadata ops, closed in [close].
  SSHClient? _sharedClient;

  int _nextTransferId = 1;
  final _transfers = StreamController<SftpEvent>.broadcast();
  var _closed = false;

  /// Runs [command] via the injected runner if present, else over the shared
  /// client (opened on first use).
  Future<CommandResult> _runner(String command) async {
    final injected = _injectedRunner;
    if (injected != null) return injected(command);
    final client = await _client();
    return execOverClient(client, command);
  }

  Future<SSHClient> _client() async {
    final existing = _sharedClient;
    if (existing != null) return existing;
    final c = await connectDockerSsh(_base);
    _sharedClient = c;
    return c;
  }

  /// Builds `docker exec <id> sh -c '<shellCmd>'` with the inner command
  /// single-quoted (and any embedded single quotes escaped via '\'').
  String _exec(String shellCmd) =>
      "$_bin exec $_containerId sh -c '${shellCmd.replaceAll("'", r"'\''")}'";

  Future<void> _runOk(String shellCmd) async {
    final res = await _runner(_exec(shellCmd));
    if (res.exitCode != 0) {
      final msg = res.stderr.trim();
      throw SftpException('op', msg.isEmpty ? 'docker exec failed' : msg);
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final res = await _runner('$_bin exec $_containerId ls -la ${_q(path)}');
    if (res.exitCode != 0) {
      final msg = res.stderr.trim();
      throw SftpException('op', msg.isEmpty ? 'ls failed' : msg);
    }
    return parseLsLa(path, res.stdout);
  }

  @override
  Future<RemoteEntry?> stat(String path) async {
    final res = await _runner('$_bin exec $_containerId ls -lad ${_q(path)}');
    if (res.exitCode != 0) return null;
    final entries = parseLsLa(_parent(path), res.stdout);
    return entries.isEmpty ? null : entries.first;
  }

  @override
  Future<void> mkdir(String path) => _runOk('mkdir -p ${_q(path)}');

  @override
  Future<void> rename(String from, String to) =>
      _runOk('mv ${_q(from)} ${_q(to)}');

  @override
  Future<void> remove(String path, {required bool isDir}) =>
      _runOk('${isDir ? 'rm -rf' : 'rm -f'} ${_q(path)}');

  @override
  Future<void> chmod(String path, int mode) =>
      _runOk('chmod ${mode.toRadixString(8).padLeft(3, '0')} ${_q(path)}');

  @override
  int startDownload(String remotePath, String localFinalPath) {
    final id = _nextTransferId++;
    unawaited(downloadViaCp(
        _base, _bin, _containerId, remotePath, localFinalPath, id, _emit));
    return id;
  }

  @override
  int startUpload(String localPath, String remoteFinalPath) {
    final id = _nextTransferId++;
    unawaited(uploadViaCp(
        _base, _bin, _containerId, localPath, remoteFinalPath, id, _emit));
    return id;
  }

  /// Guards against emitting onto a closed controller (a transfer may finish
  /// after [close]).
  void _emit(SftpEvent event) {
    if (!_closed) _transfers.add(event);
  }

  @override
  void cancel(int transferId) {
    // v1: best-effort no-op. Transfers are short single-file streams; a true
    // cancel (tear down the docker cp channel mid-stream) is a follow-up.
  }

  @override
  Stream<SftpEvent> get transfers => _transfers.stream;

  @override
  Future<void> close() async {
    _closed = true;
    _sharedClient?.close();
    _sharedClient = null;
    await _transfers.close();
  }

  /// Single-quotes [p] for `sh`, escaping embedded single quotes via '\''.
  /// Delegates to the shared [shellSingleQuote] so backend + worker use one
  /// implementation.
  static String _q(String p) => shellSingleQuote(p);

  static String _parent(String p) {
    final i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }
}
