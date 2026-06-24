import 'dart:convert';

import '../sftp/remote_file_ops.dart';
import '../ssh/terminal_session.dart';

/// A container as reported by `docker ps`. Runtime-only; never persisted.
class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String state; // running | exited | paused | created | ...
  final String status; // human-readable, e.g. "Up 3 hours"
  final List<String> ports;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.ports,
  });

  bool get isRunning => state == 'running';
}

/// Parses one line of `docker ps --format '{{json .}}'`. Returns null on any
/// malformed/incomplete line so a single bad row never breaks the whole list
/// (defensive parse — ADR 0015).
DockerContainer? parseDockerPsLine(String jsonLine) {
  final trimmed = jsonLine.trim();
  if (trimmed.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final id = decoded['ID'];
  final name = decoded['Names'];
  if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
    return null;
  }
  final portsRaw = (decoded['Ports'] as String?)?.trim() ?? '';
  final ports = portsRaw.isEmpty
      ? <String>[]
      : portsRaw.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  return DockerContainer(
    id: id,
    name: name,
    image: (decoded['Image'] as String?) ?? '',
    state: (decoded['State'] as String?) ?? '',
    status: (decoded['Status'] as String?) ?? '',
    ports: ports,
  );
}

/// Why a Docker CLI invocation failed, mapped from the process exit code +
/// stderr so the UI can show a precise, actionable message (ADR 0028).
enum DockerErrorKind { notInstalled, denied, daemonNotRunning, unknown }

/// Raised when a Docker CLI command fails. [message] is the trimmed remote
/// stderr so the surface error stays faithful to what `docker` reported.
class DockerException implements Exception {
  final DockerErrorKind kind;
  final String message;
  DockerException(this.kind, this.message);
  @override
  String toString() => 'DockerException($kind): $message';
}

/// Backend-agnostic Docker host contract: drives a remote daemon via the
/// `docker` CLI. Implemented by [SshDockerHost] (over SSH); a local backend may
/// follow in Faz 2. See ADR 0028.
abstract class DockerHost {
  /// Lists containers (`docker ps`). When [all] is false, only running ones.
  Future<List<DockerContainer>> listContainers({bool all = true});

  /// Opens an interactive shell inside [containerId] (`docker exec -it`),
  /// returning a [TerminalSession] the xterm pane can drive like a plain shell.
  Future<TerminalSession> execShell(String containerId, {String? shell});

  /// Returns a file backend scoped to [containerId] (docker exec/cp).
  RemoteFileOps files(String containerId);

  /// Releases any shared resources (e.g. a pooled SSH client).
  Future<void> dispose();
}

/// Builds the `docker ps` command. Pure — no I/O. `--no-trunc` keeps full IDs;
/// `{{json .}}` yields one JSON object per line for [parseDockerPsLine].
String dockerPsCommand(String bin, {required bool all}) =>
    "$bin ps${all ? ' --all' : ''} --no-trunc --format '{{json .}}'";

/// Builds the interactive exec command. Pure — no I/O. Prefers `bash` and
/// falls back to `sh` so containers without bash still get a usable shell.
String dockerExecShellCommand(String bin, String containerId) =>
    "$bin exec -it $containerId sh -c 'exec bash 2>/dev/null || exec sh'";

/// Maps a failed Docker CLI invocation to a [DockerErrorKind]. Pure — no I/O.
DockerErrorKind classifyDockerError(int exitCode, String stderr) {
  final s = stderr.toLowerCase();
  if (s.contains('command not found') ||
      s.contains('executable file not found') ||
      exitCode == 127) {
    return DockerErrorKind.notInstalled;
  }
  if (s.contains('cannot connect to the docker daemon') ||
      s.contains('is the docker daemon running')) {
    return DockerErrorKind.daemonNotRunning;
  }
  if (s.contains('permission denied') ||
      s.contains('dial unix') ||
      s.contains('got permission denied')) {
    return DockerErrorKind.denied;
  }
  return DockerErrorKind.unknown;
}
