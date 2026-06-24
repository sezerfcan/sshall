import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'fingerprint.dart';
import 'ssh_messages.dart';

/// Isolate entry point. Owns the SSHClient + PTY for one session.
///
/// The connection runs as a fire-and-forget task (not awaited inside the
/// message loop) so the loop keeps processing commands — crucially the
/// HostKeyDecisionCommand that unblocks onVerifyHostKey during authentication.
/// The session's owner (UI) terminates the worker by sending CloseCommand.
Future<void> sshWorkerMain(SendPort toUi) async {
  final commands = ReceivePort();
  toUi.send(commands.sendPort); // hand the command port back to the UI isolate

  SSHClient? client;
  SSHSession? shell;
  StreamSubscription<Uint8List>? stdoutSub;
  StreamSubscription<Uint8List>? stderrSub;
  Completer<bool>? hostKeyDecision;
  var hostKeyRejected = false;

  void teardown() {
    // Cancel the output subscriptions before closing the shell so no late
    // chunk is forwarded to a UI port that is about to go away (mirrors the
    // SFTP worker's deterministic teardown). Fire-and-forget cancel is fine —
    // the isolate is exiting right after.
    stdoutSub?.cancel();
    stderrSub?.cancel();
    shell?.close();
    client?.close();
  }

  Future<void> doConnect(SshConnectParams p) async {
    try {
      toUi.send(StatusEvent(SshStatus.connecting));
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
          toUi.send(HostKeyRequestEvent(type, formatSha256(fp)));
          return hostKeyDecision!.future;
        },
      );
      client = c;
      toUi.send(StatusEvent(SshStatus.authenticating));
      await c.authenticated;
      const pty =
          SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24);
      // When execCommand is set (e.g. `docker exec -it ...`), open an exec
      // channel running that command over a PTY instead of a login shell.
      // execute() and shell() both return SSHSession, so all downstream
      // wiring (stdout/stderr listen, s.done teardown, ready status) is
      // identical for either branch.
      final s = p.execCommand != null
          ? await c.execute(p.execCommand!, pty: pty)
          : await c.shell(pty: pty);
      shell = s;
      // Keep the subscriptions so teardown() can cancel them; an unstored
      // listen() would keep forwarding chunks to toUi after close.
      stdoutSub = s.stdout.listen((d) => toUi.send(OutputEvent(d)));
      stderrSub = s.stderr.listen((d) => toUi.send(OutputEvent(d)));
      // When the remote shell ends (user typed `exit`, dropped connection,
      // server-side kill) drive the SAME teardown path as an explicit close, so
      // the isolate actually exits instead of lingering with a live socket and
      // keep-alive timer. catchError mirrors the SFTP worker's c.done handling:
      // if `done` completes with an error, drive the same close path instead of
      // leaving an uncaught async error (which could skip the CloseCommand
      // self-send and leave the isolate alive).
      s.done
          .then((_) => commands.sendPort.send(CloseCommand()))
          .catchError((_) => commands.sendPort.send(CloseCommand()));
      toUi.send(StatusEvent(SshStatus.ready));
    } on SSHAuthFailError catch (e) {
      toUi.send(ErrorEvent('auth', e.message));
      teardown();
      toUi.send(ClosedEvent());
    } on SSHKeyDecryptError catch (e) {
      toUi.send(ErrorEvent('auth', e.message));
      teardown();
      toUi.send(ClosedEvent());
    } on FormatException catch (_) {
      toUi.send(ErrorEvent('auth', 'Could not import private key'));
      teardown();
      toUi.send(ClosedEvent());
    } on ArgumentError catch (_) {
      toUi.send(ErrorEvent('auth', 'Could not import private key'));
      teardown();
      toUi.send(ClosedEvent());
    } catch (e) {
      toUi.send(hostKeyRejected
          ? ErrorEvent('hostkey', 'Host key rejected')
          : ErrorEvent('network', e.toString()));
      teardown();
      toUi.send(ClosedEvent());
    }
  }

  await for (final msg in commands) {
    if (msg is ConnectCommand) {
      // Fire-and-forget: must NOT await here, or the loop cannot process the
      // HostKeyDecisionCommand that unblocks authentication.
      unawaited(doConnect(msg.params));
    } else if (msg is HostKeyDecisionCommand) {
      if (!msg.accept) hostKeyRejected = true;
      if (hostKeyDecision?.isCompleted == false) {
        hostKeyDecision!.complete(msg.accept);
      }
    } else if (msg is StdinCommand) {
      shell?.write(msg.data);
    } else if (msg is ResizeCommand) {
      shell?.resizeTerminal(
          msg.width, msg.height, msg.pixelWidth, msg.pixelHeight);
    } else if (msg is CloseCommand) {
      teardown();
      // Deliver the final close event ATOMICALLY with isolate termination.
      // `toUi.send(...)` then a plain `Isolate.exit()` does NOT guarantee the
      // queued-but-undelivered message arrives; the isolate can die first and
      // the UI would never observe ClosedEvent. `Isolate.exit(port, message)`
      // guarantees this last send is delivered as the isolate exits.
      commands.close();
      Isolate.exit(toUi, ClosedEvent());
    }
  }
  commands.close();
  Isolate.exit();
}
