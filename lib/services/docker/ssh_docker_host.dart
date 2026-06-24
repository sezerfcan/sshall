import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../sftp/remote_file_ops.dart';
import '../ssh/ssh_messages.dart';
import '../ssh/ssh_service.dart';
import '../ssh/terminal_session.dart';
import 'docker_file_backend.dart';
import 'docker_host.dart';

/// Result of a one-shot, non-interactive remote command.
class CommandResult {
  final int exitCode;
  final String stdout, stderr;
  CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Runs [command] to completion and returns its captured output. The default
/// runner executes over a shared dartssh2 client; tests inject a fake.
typedef CommandRunner = Future<CommandResult> Function(String command);

/// Drives a remote Docker daemon via the `docker` CLI over SSH. v1 — ADR 0028.
///
/// Two distinct I/O paths:
///  - non-interactive commands (`docker ps`, later file ops) go through the
///    [_run]/[runner] seam — a one-shot exec channel whose output is collected;
///  - [execShell] opens an interactive PTY exec channel via [SshService], the
///    same pipeline as a plain login shell, so it does NOT use [_run].
class SshDockerHost implements DockerHost {
  SshDockerHost(
    this._base, {
    String binary = 'docker',
    CommandRunner? runner,
    SshService? ssh,
  })  : _bin = binary,
        _runner = runner,
        _ssh = ssh ?? SshService();

  final SshConnectParams _base;
  final String _bin;
  final CommandRunner? _runner;
  final SshService _ssh;
  SSHClient? _sharedClient; // lazily opened for the default runner

  /// Runs [command] via the injected runner if present, else over a shared
  /// dartssh2 client. Drains stdout/stderr fully (more data may arrive after
  /// `done`, per the SSHSession contract) before reading the exit code.
  Future<CommandResult> _run(String command) async {
    final injected = _runner;
    if (injected != null) return injected(command);
    final client = await _client();
    final session = await client.execute(command);
    final out = <int>[];
    final err = <int>[];
    final outDone = session.stdout.listen(out.addAll).asFuture<void>();
    final errDone = session.stderr.listen(err.addAll).asFuture<void>();
    await Future.wait([outDone, errDone]);
    final code = session.exitCode ?? 0;
    return CommandResult(
      exitCode: code,
      stdout: utf8.decode(out, allowMalformed: true),
      stderr: utf8.decode(err, allowMalformed: true),
    );
  }

  /// Lazily opens (and caches) the SSH client used by the default runner.
  Future<SSHClient> _client() async {
    final existing = _sharedClient;
    if (existing != null) return existing;
    final socket = await SSHSocket.connect(_base.host, _base.port,
        timeout: const Duration(seconds: 10));
    final c = SSHClient(
      socket,
      username: _base.username,
      onPasswordRequest: _base.password != null ? () => _base.password! : null,
      identities: _base.privateKeyPem != null
          ? SSHKeyPair.fromPem(_base.privateKeyPem!, _base.keyPassphrase)
          : null,
    );
    await c.authenticated;
    _sharedClient = c;
    return c;
  }

  @override
  Future<List<DockerContainer>> listContainers({bool all = true}) async {
    final res = await _run(dockerPsCommand(_bin, all: all));
    if (res.exitCode != 0) {
      final kind = classifyDockerError(res.exitCode, res.stderr);
      throw DockerException(kind, res.stderr.trim());
    }
    final list = <DockerContainer>[];
    for (final line in res.stdout.split('\n')) {
      final c = parseDockerPsLine(line);
      if (c != null) list.add(c);
    }
    return list;
  }

  @override
  Future<TerminalSession> execShell(String containerId, {String? shell}) async {
    final cmd = shell == null
        ? dockerExecShellCommand(_bin, containerId)
        : "$_bin exec -it $containerId $shell";
    final params = SshConnectParams(
      host: _base.host,
      port: _base.port,
      username: _base.username,
      password: _base.password,
      privateKeyPem: _base.privateKeyPem,
      keyPassphrase: _base.keyPassphrase,
      execCommand: cmd,
    );
    return _ssh.connect(params); // SshSession implements TerminalSession
  }

  @override
  RemoteFileOps files(String containerId) =>
      DockerFileBackend(_base, containerId, binary: _bin);

  @override
  Future<void> dispose() async {
    _sharedClient?.close();
    _sharedClient = null;
  }
}
