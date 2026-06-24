import '../ssh/ssh_messages.dart' show SshConnectParams;

export '../ssh/ssh_messages.dart' show SshConnectParams;

enum SftpStatus { connecting, authenticating, ready, closed }

// ---- operations (request payloads that yield an SftpReply) ----
sealed class SftpOp {}

class ListDir extends SftpOp {
  final String path;
  ListDir(this.path);
}

class Mkdir extends SftpOp {
  final String path;
  Mkdir(this.path);
}

class Rename extends SftpOp {
  final String from, to;
  Rename(this.from, this.to);
}

class Remove extends SftpOp {
  final String path;
  final bool isDir;
  Remove(this.path, this.isDir);
}

class Chmod extends SftpOp {
  final String path;
  final int mode;
  Chmod(this.path, this.mode);
}

class StatOp extends SftpOp {
  final String path;
  StatOp(this.path);
}

// ---- commands (UI -> worker) ----
sealed class SftpCommand {}

class SftpConnect extends SftpCommand {
  final SshConnectParams params;
  SftpConnect(this.params);
}

class SftpHostKeyDecision extends SftpCommand {
  final bool accept;
  SftpHostKeyDecision(this.accept);
}

class SftpRpc extends SftpCommand {
  final int id;
  final SftpOp op;
  SftpRpc(this.id, this.op);
}

class SftpStartDownload extends SftpCommand {
  final int transferId;
  final String remotePath, localFinalPath;
  SftpStartDownload(this.transferId, this.remotePath, this.localFinalPath);
}

class SftpStartUpload extends SftpCommand {
  final int transferId;
  final String localPath, remoteFinalPath;
  SftpStartUpload(this.transferId, this.localPath, this.remoteFinalPath);
}

class SftpCancel extends SftpCommand {
  final int transferId;
  SftpCancel(this.transferId);
}

class SftpClose extends SftpCommand {}

// ---- events (worker -> UI) ----
sealed class SftpEvent {}

class SftpStatusEvent extends SftpEvent {
  final SftpStatus status;
  SftpStatusEvent(this.status);
}

class SftpHostKeyRequest extends SftpEvent {
  final String keyType, sha256;
  SftpHostKeyRequest(this.keyType, this.sha256);
}

class SftpReply extends SftpEvent {
  final int id;
  final Object? value;
  final String? errCode;
  final String? errMessage;
  SftpReply.ok(this.id, this.value)
      : errCode = null,
        errMessage = null;
  SftpReply.err(this.id, this.errCode, this.errMessage) : value = null;
  bool get isOk => errCode == null;
}

class TransferProgress extends SftpEvent {
  final int transferId, bytes;
  final int? total;
  TransferProgress(this.transferId, this.bytes, this.total);
}

class TransferDone extends SftpEvent {
  final int transferId;
  final String finalPath;
  TransferDone(this.transferId, this.finalPath);
}

class TransferFailed extends SftpEvent {
  final int transferId;
  final String message;
  TransferFailed(this.transferId, this.message);
}

class SftpConnectError extends SftpEvent {
  final String code, message;
  SftpConnectError(this.code, this.message);
}

class SftpClosedEvent extends SftpEvent {}
