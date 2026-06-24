import 'dart:io';

import '../sftp/remote_file_ops.dart';
import '../ssh/terminal_session.dart';
import 'docker_host.dart';
import 'local_docker_file_backend.dart';
import 'pty_terminal_session.dart';

/// [DockerHost] backed by the LOCAL `docker` CLI (`Process`) + flutter_pty for
/// the interactive terminal. Reuses v1's [parseDockerPsLine]/[classifyDockerError].
/// Only works because macOS App Sandbox is dropped (ADR 0029). See ADR 0028.
class LocalDockerHost implements DockerHost {
  LocalDockerHost({String binary = 'docker', ProcessRunner? runner})
      : _bin = binary,
        _run = runner ?? Process.run;

  final String _bin;
  final ProcessRunner _run;

  @override
  Future<List<DockerContainer>> listContainers({bool all = true}) async {
    ProcessResult res;
    try {
      res = await _run(_bin, [
        'ps',
        if (all) '--all',
        '--no-trunc',
        '--format',
        '{{json .}}',
      ]);
    } on ProcessException catch (e) {
      // The binary isn't on PATH / not installed.
      throw DockerException(DockerErrorKind.notInstalled, e.message);
    }
    if (res.exitCode != 0) {
      final err = (res.stderr as String? ?? '').trim();
      throw DockerException(classifyDockerError(res.exitCode, err), err);
    }
    final out = res.stdout as String? ?? '';
    final list = <DockerContainer>[];
    for (final line in out.split('\n')) {
      final c = parseDockerPsLine(line);
      if (c != null) list.add(c);
    }
    return list;
  }

  @override
  Future<TerminalSession> execShell(String containerId, {String? shell}) async {
    final args = shell == null
        ? ['exec', '-it', containerId, 'sh', '-c', 'exec bash 2>/dev/null || exec sh']
        : ['exec', '-it', containerId, shell];
    return PtyTerminalSession.start(_bin, arguments: args);
  }

  @override
  RemoteFileOps files(String containerId) =>
      LocalDockerFileBackend(_bin, containerId, runner: _run);

  @override
  Future<void> dispose() async {} // Process-based; nothing pooled.
}
