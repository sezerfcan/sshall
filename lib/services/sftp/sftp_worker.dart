import 'dart:async';
import 'dart:isolate';

import 'package:dartssh2/dartssh2.dart';

import '../../data/models/remote_entry.dart';
import '../ssh/fingerprint.dart';
import 'remote_path.dart';
import 'sftp_messages.dart';
import 'sftp_transfer.dart';
import 'sftp_transfer_dartssh2.dart';

/// Isolate entry point. Owns the SSHClient + SftpClient for one SFTP session.
Future<void> sftpWorkerMain(SendPort toUi) async {
  final commands = ReceivePort();
  toUi.send(commands.sendPort);

  SSHClient? client;
  SftpClient? sftp;
  // Transfer core. Built once the SftpClient is ready (see doConnect). The
  // worker delegates every download/upload/cancel to this engine — there is no
  // duplicate, untested copy of the transfer logic. See ADR 0014.
  SftpTransferEngine? engine;
  Completer<bool>? hostKeyDecision;
  var hostKeyRejected = false;

  void teardown() {
    sftp?.close();
    client?.close();
  }

  RemoteEntry toEntry(String parent, SftpName n) {
    final a = n.attr;
    final mtime = a.modifyTime;
    return RemoteEntry(
      name: n.filename,
      path: RemotePath.join(parent, n.filename),
      isDir: a.isDirectory,
      isSymlink: a.isSymbolicLink,
      size: a.size ?? 0,
      modified:
          mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
      mode: a.mode?.value,
    );
  }

  String mapErr(Object e) {
    if (e is SftpStatusError) return e.message;
    return e.toString();
  }

  Future<void> doConnect(SshConnectParams p) async {
    try {
      toUi.send(SftpStatusEvent(SftpStatus.connecting));
      final socket = await SSHSocket.connect(p.host, p.port,
          timeout: const Duration(seconds: 10));
      final c = SSHClient(
        socket,
        username: p.username,
        onPasswordRequest: p.password != null ? () => p.password! : null,
        identities: p.privateKeyPem != null
            ? SSHKeyPair.fromPem(p.privateKeyPem!, p.keyPassphrase)
            : null,
        keepAliveInterval: const Duration(seconds: 15),
        onVerifyHostKey: (type, fp) {
          hostKeyDecision = Completer<bool>();
          toUi.send(SftpHostKeyRequest(type, formatSha256(fp)));
          return hostKeyDecision!.future;
        },
      );
      client = c;
      // When the connection closes (normal end, dropped connection, server-side
      // kill) drive the SAME teardown path as an explicit close, so the isolate
      // actually exits instead of lingering with a live socket and keep-alive
      // timer.
      c.done
          .then((_) => commands.sendPort.send(SftpClose()))
          .catchError((_) => commands.sendPort.send(SftpClose()));
      toUi.send(SftpStatusEvent(SftpStatus.authenticating));
      await c.authenticated;
      final s = await c.sftp();
      sftp = s;
      // Wire the pure transfer engine to production adapters + the UI port.
      engine = SftpTransferEngine(
        remoteFs: DartSftpRemoteFs(s),
        localFs: const DartLocalFs(),
        emit: toUi.send,
        mapErr: mapErr,
      );
      toUi.send(SftpStatusEvent(SftpStatus.ready));
    } on SSHAuthFailError catch (e) {
      toUi.send(SftpConnectError('auth', e.message));
      teardown();
      toUi.send(SftpClosedEvent());
    } on SSHKeyDecryptError catch (e) {
      toUi.send(SftpConnectError('auth', e.message));
      teardown();
      toUi.send(SftpClosedEvent());
    } catch (e) {
      toUi.send(hostKeyRejected
          ? SftpConnectError('hostkey', 'Host key rejected')
          : SftpConnectError('network', e.toString()));
      teardown();
      toUi.send(SftpClosedEvent());
    }
  }

  Future<void> handleRpc(int id, SftpOp op) async {
    final s = sftp;
    if (s == null) {
      toUi.send(SftpReply.err(id, 'closed', 'Oturum hazır değil'));
      return;
    }
    try {
      switch (op) {
        case ListDir(:final path):
          final names = await s.listdir(path);
          final entries = <RemoteEntry>[];
          for (final n in names) {
            if (n.filename == '.' || n.filename == '..') continue;
            entries.add(toEntry(path, n));
          }
          toUi.send(SftpReply.ok(id, entries));
        case Mkdir(:final path):
          await s.mkdir(path);
          toUi.send(SftpReply.ok(id, null));
        case Rename(:final from, :final to):
          await s.rename(from, to);
          toUi.send(SftpReply.ok(id, null));
        case Remove(:final path, :final isDir):
          if (isDir) {
            await s.rmdir(path);
          } else {
            await s.remove(path);
          }
          toUi.send(SftpReply.ok(id, null));
        case Chmod(:final path, :final mode):
          await s.setStat(path, SftpFileAttrs(mode: SftpFileMode.value(mode)));
          toUi.send(SftpReply.ok(id, null));
        case StatOp(:final path):
          try {
            final a = await s.stat(path);
            final mtime = a.modifyTime;
            toUi.send(SftpReply.ok(
                id,
                RemoteEntry(
                  name: path.split('/').last,
                  path: path,
                  isDir: a.isDirectory,
                  isSymlink: a.isSymbolicLink,
                  size: a.size ?? 0,
                  modified: mtime == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
                  mode: a.mode?.value,
                )));
          } on SftpStatusError {
            toUi.send(SftpReply.ok(id, null)); // not found -> null
          }
      }
    } catch (e) {
      toUi.send(SftpReply.err(id, 'op', mapErr(e)));
    }
  }

  // Delegate transfers to the pure engine. The engine only exists once the
  // SftpClient is ready; before that we keep the original "session not ready"
  // failure (the engine never sees an unconnected session).
  Future<void> doDownload(int tid, String remotePath, String localFinal) async {
    final e = engine;
    if (e == null) {
      toUi.send(TransferFailed(tid, 'Oturum hazır değil'));
      return;
    }
    await e.download(tid, remotePath, localFinal);
  }

  Future<void> doUpload(int tid, String localPath, String remoteFinal) async {
    final e = engine;
    if (e == null) {
      toUi.send(TransferFailed(tid, 'Oturum hazır değil'));
      return;
    }
    await e.upload(tid, localPath, remoteFinal);
  }

  await for (final msg in commands) {
    if (msg is SftpConnect) {
      unawaited(doConnect(msg.params));
    } else if (msg is SftpHostKeyDecision) {
      if (!msg.accept) hostKeyRejected = true;
      if (hostKeyDecision?.isCompleted == false) {
        hostKeyDecision!.complete(msg.accept);
      }
    } else if (msg is SftpRpc) {
      unawaited(handleRpc(msg.id, msg.op));
    } else if (msg is SftpStartDownload) {
      unawaited(doDownload(msg.transferId, msg.remotePath, msg.localFinalPath));
    } else if (msg is SftpStartUpload) {
      unawaited(doUpload(msg.transferId, msg.localPath, msg.remoteFinalPath));
    } else if (msg is SftpCancel) {
      engine?.cancel(msg.transferId);
    } else if (msg is SftpClose) {
      teardown();
      // Deliver the final close event ATOMICALLY with isolate termination.
      // `toUi.send(...)` followed by a plain `Isolate.exit()` does NOT guarantee
      // the queued-but-undelivered message arrives — the isolate can die first,
      // leaving the UI with hung RPC Completers that never see SftpClosedEvent
      // (so _failPending never runs). `Isolate.exit(port, message)` guarantees
      // this last send is delivered as the isolate exits.
      commands.close();
      Isolate.exit(toUi, SftpClosedEvent());
    }
  }
  commands.close();
  Isolate.exit();
}
