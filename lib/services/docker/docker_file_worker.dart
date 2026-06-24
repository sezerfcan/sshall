import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dartssh2/dartssh2.dart';

import '../sftp/sftp_messages.dart';
import 'shell_quote.dart';
import 'ssh_docker_host.dart' show CommandResult;

/// Builds the `docker cp <id>:<remote> -` download command with [containerId]
/// and [remotePath] shell-quoted. The `<id>:<path>` colon stays OUTSIDE the
/// quotes: adjacent quoted strings with no separating space concatenate into a
/// single shell argument, so `'id':'path'` → one arg `id:path` (what
/// `docker cp` expects). Pure + side-effect free for unit testing.
String dockerCpDownloadCommand(
        String bin, String containerId, String remotePath) =>
    '$bin cp ${shellSingleQuote(containerId)}:${shellSingleQuote(remotePath)} -';

/// Builds the `docker cp - <id>:<destDir>` upload command with [containerId]
/// and [destDir] shell-quoted (colon outside the quotes, see
/// [dockerCpDownloadCommand]). Pure + side-effect free for unit testing.
String dockerCpUploadCommand(String bin, String containerId, String destDir) =>
    '$bin cp - ${shellSingleQuote(containerId)}:${shellSingleQuote(destDir)}';

/// Transfer + exec helpers behind [DockerFileBackend]. Metadata ops use
/// [execOverClient] over a shared client; transfers open a dedicated client
/// each (long-lived byte streams must not contend with folder browsing). See
/// ADR 0028.

/// Runs [command] to completion on an already-connected [client] and returns
/// its captured output. Used by the backend's default metadata runner over the
/// shared client. Drains stdout/stderr fully before reading the exit code (more
/// data may arrive after `done`, per the SSHSession contract).
Future<CommandResult> execOverClient(SSHClient client, String command) async {
  final session = await client.execute(command);
  final out = <int>[];
  final err = <int>[];
  final outDone = session.stdout.listen(out.addAll).asFuture<void>();
  final errDone = session.stderr.listen(err.addAll).asFuture<void>();
  await Future.wait([outDone, errDone]);
  return CommandResult(
    exitCode: session.exitCode ?? 0,
    stdout: utf8.decode(out, allowMalformed: true),
    stderr: utf8.decode(err, allowMalformed: true),
  );
}

/// One-shot non-interactive command over a fresh SSH client. Retained for the
/// per-call fallback; the backend prefers the shared-client path.
Future<CommandResult> execOverSsh(SshConnectParams base, String command) async {
  final client = await connectDockerSsh(base);
  try {
    return await execOverClient(client, command);
  } finally {
    client.close();
  }
}

/// Download: `docker cp <id>:<remote> -` → tar on stdout → extract single file
/// → atomic `.part` → rename. Emits [TransferProgress]/[TransferDone]/
/// [TransferFailed] on [emit].
Future<void> downloadViaCp(
  SshConnectParams base,
  String bin,
  String containerId,
  String remotePath,
  String localFinalPath,
  int transferId,
  void Function(SftpEvent) emit,
) async {
  final client = await connectDockerSsh(base);
  try {
    final s = await client
        .execute(dockerCpDownloadCommand(bin, containerId, remotePath));
    final bytes = <int>[];
    final err = <int>[];
    var received = 0;
    final outDone = s.stdout.listen((chunk) {
      bytes.addAll(chunk);
      received += chunk.length;
      emit(TransferProgress(transferId, received, null));
    }).asFuture<void>();
    final errDone = s.stderr.listen(err.addAll).asFuture<void>();
    await Future.wait([outDone, errDone]);
    if ((s.exitCode ?? 0) != 0) {
      final msg = utf8.decode(err, allowMalformed: true).trim();
      emit(TransferFailed(
          transferId, msg.isEmpty ? 'docker cp failed' : msg));
      return;
    }
    final archive = TarDecoder().decodeBytes(bytes);
    final file = archive.files.firstWhere(
      (f) => f.isFile,
      orElse: () => throw StateError('tar stream contained no file'),
    );
    final part = File('$localFinalPath.part');
    await part.writeAsBytes(file.content, flush: true);
    await part.rename(localFinalPath);
    emit(TransferDone(transferId, localFinalPath));
  } catch (e) {
    emit(TransferFailed(transferId, e.toString()));
  } finally {
    client.close();
  }
}

/// Upload: tar the single local file → `docker cp - <id>:<destDir>` over stdin.
/// Emits [TransferProgress]/[TransferDone]/[TransferFailed] on [emit].
Future<void> uploadViaCp(
  SshConnectParams base,
  String bin,
  String containerId,
  String localPath,
  String remoteFinalPath,
  int transferId,
  void Function(SftpEvent) emit,
) async {
  final client = await connectDockerSsh(base);
  try {
    final data = await File(localPath).readAsBytes();
    final slash = remoteFinalPath.lastIndexOf('/');
    final name = slash < 0 ? remoteFinalPath : remoteFinalPath.substring(slash + 1);
    final destDir = slash <= 0 ? '/' : remoteFinalPath.substring(0, slash);
    final ar = Archive()..addFile(ArchiveFile(name, data.length, data));
    final tar = TarEncoder().encode(ar);
    final s = await client
        .execute(dockerCpUploadCommand(bin, containerId, destDir));
    final err = <int>[];
    final errDone = s.stderr.listen(err.addAll).asFuture<void>();
    s.stdin.add(Uint8List.fromList(tar));
    await s.stdin.close();
    emit(TransferProgress(transferId, data.length, data.length));
    await s.done;
    await errDone;
    if ((s.exitCode ?? 0) != 0) {
      final msg = utf8.decode(err, allowMalformed: true).trim();
      emit(TransferFailed(
          transferId, msg.isEmpty ? 'docker cp failed' : msg));
      return;
    }
    emit(TransferDone(transferId, remoteFinalPath));
  } catch (e) {
    emit(TransferFailed(transferId, e.toString()));
  } finally {
    client.close();
  }
}

/// Opens an authenticated SSH client for the docker host. Mirrors the SFTP/SSH
/// worker connection pattern.
///
/// Host-key note: this path auto-accepts (no `onVerifyHostKey`) because the
/// container host was already trusted when the SSH connection was registered.
/// Strict host-key reuse can be threaded through [SshConnectParams] later; v1
/// relies on the already-trusted host. See ADR 0028.
Future<SSHClient> connectDockerSsh(SshConnectParams base) async {
  final socket = await SSHSocket.connect(base.host, base.port,
      timeout: const Duration(seconds: 10));
  final c = SSHClient(
    socket,
    username: base.username,
    onPasswordRequest: base.password != null ? () => base.password! : null,
    identities: base.privateKeyPem != null
        ? SSHKeyPair.fromPem(base.privateKeyPem!, base.keyPassphrase)
        : null,
  );
  await c.authenticated;
  return c;
}
