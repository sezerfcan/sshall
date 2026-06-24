import 'dart:typed_data';

class SshConnectParams {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPem;
  final String? keyPassphrase;

  /// When set, the worker opens an exec channel running this command (with a PTY)
  /// instead of a login shell — used for `docker exec -it ...`. See ADR 0028.
  final String? execCommand;

  const SshConnectParams({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPem,
    this.keyPassphrase,
    this.execCommand,
  });
}

enum SshStatus { connecting, authenticating, ready, closed }

sealed class WorkerCommand {}

class ConnectCommand extends WorkerCommand {
  final SshConnectParams params;
  ConnectCommand(this.params);
}

class StdinCommand extends WorkerCommand {
  final Uint8List data;
  StdinCommand(this.data);
}

class ResizeCommand extends WorkerCommand {
  final int width, height, pixelWidth, pixelHeight;
  ResizeCommand(this.width, this.height, this.pixelWidth, this.pixelHeight);
}

class HostKeyDecisionCommand extends WorkerCommand {
  final bool accept;
  HostKeyDecisionCommand(this.accept);
}

class CloseCommand extends WorkerCommand {}

sealed class WorkerEvent {}

class OutputEvent extends WorkerEvent {
  final Uint8List data;
  OutputEvent(this.data);
}

class StatusEvent extends WorkerEvent {
  final SshStatus status;
  StatusEvent(this.status);
}

class HostKeyRequestEvent extends WorkerEvent {
  final String keyType;
  final String sha256;
  HostKeyRequestEvent(this.keyType, this.sha256);
}

class ErrorEvent extends WorkerEvent {
  final String code; // 'auth' | 'network' | 'hostkey' | 'unknown'
  final String message;
  ErrorEvent(this.code, this.message);
}

class ClosedEvent extends WorkerEvent {}
