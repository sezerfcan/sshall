import 'dart:async';
import 'dart:isolate';

import '../../data/models/remote_entry.dart';
import 'remote_file_ops.dart';
import 'sftp_messages.dart';
import 'sftp_worker.dart';

class SftpException implements Exception {
  final String code, message;
  SftpException(this.code, this.message);
  @override
  String toString() => 'SftpException($code): $message';
}

class SftpSession implements RemoteFileOps {
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  int _nextRpcId = 1;
  int _nextTransferId = 1;
  final _pending = <int, Completer<Object?>>{};

  final _status = StreamController<SftpStatus>.broadcast();
  final _hostKey = StreamController<SftpHostKeyRequest>.broadcast();
  final _transfers = StreamController<SftpEvent>.broadcast();
  final _connectErrors = StreamController<SftpConnectError>.broadcast();

  /// Test constructor: the [fromWorker] [ReceivePort] is single-subscription,
  /// which is fine here because only the session listens to it.
  SftpSession.fromPorts(this._toWorker, this._fromWorker) {
    _fromWorker.listen((msg) {
      if (msg is SftpEvent) _handle(msg);
    });
  }

  /// Real-path constructor: the handshake listener already consumed the first
  /// message from a broadcast view of [fromWorker], so the session subscribes
  /// to that same [events] stream. [_fromWorker] is retained only so [close]
  /// can call `_fromWorker.close()`.
  SftpSession.fromStream(
      this._toWorker, this._fromWorker, Stream<dynamic> events) {
    events.listen((msg) {
      if (msg is SftpEvent) _handle(msg);
    });
  }

  Stream<SftpStatus> get status => _status.stream;
  Stream<SftpHostKeyRequest> get hostKeyRequests => _hostKey.stream;
  @override
  Stream<SftpEvent> get transfers => _transfers.stream;
  Stream<SftpConnectError> get connectErrors => _connectErrors.stream;

  void _handle(SftpEvent e) {
    switch (e) {
      case SftpReply():
        final c = _pending.remove(e.id);
        if (c == null) return;
        if (e.isOk) {
          c.complete(e.value);
        } else {
          c.completeError(SftpException(e.errCode!, e.errMessage!));
        }
      case SftpStatusEvent():
        if (!_status.isClosed) _status.add(e.status);
      case SftpHostKeyRequest():
        if (!_hostKey.isClosed) _hostKey.add(e);
      case TransferProgress():
      case TransferDone():
      case TransferFailed():
        if (!_transfers.isClosed) _transfers.add(e);
      case SftpConnectError():
        if (!_connectErrors.isClosed) _connectErrors.add(e);
      case SftpClosedEvent():
        if (!_status.isClosed) _status.add(SftpStatus.closed);
        _failPending('closed', 'Bağlantı kapandı');
    }
  }

  void _failPending(String code, String message) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(SftpException(code, message));
    }
  }

  Future<Object?> _rpc(SftpOp op) {
    final id = _nextRpcId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _toWorker.send(SftpRpc(id, op));
    return c.future;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async =>
      ((await _rpc(ListDir(path)) as List).cast<RemoteEntry>());
  @override
  Future<void> mkdir(String path) async => await _rpc(Mkdir(path));
  @override
  Future<void> rename(String from, String to) async =>
      await _rpc(Rename(from, to));
  @override
  Future<void> remove(String path, {required bool isDir}) async =>
      await _rpc(Remove(path, isDir));
  @override
  Future<void> chmod(String path, int mode) async =>
      await _rpc(Chmod(path, mode));
  @override
  Future<RemoteEntry?> stat(String path) async =>
      (await _rpc(StatOp(path))) as RemoteEntry?;

  @override
  int startDownload(String remotePath, String localFinalPath) {
    final id = _nextTransferId++;
    _toWorker.send(SftpStartDownload(id, remotePath, localFinalPath));
    return id;
  }

  @override
  int startUpload(String localPath, String remoteFinalPath) {
    final id = _nextTransferId++;
    _toWorker.send(SftpStartUpload(id, localPath, remoteFinalPath));
    return id;
  }

  @override
  void cancel(int transferId) => _toWorker.send(SftpCancel(transferId));
  void decideHostKey(bool accept) =>
      _toWorker.send(SftpHostKeyDecision(accept));

  @override
  Future<void> close() async {
    _toWorker.send(SftpClose());
    _failPending('closed', 'Bağlantı kapandı');
    await _status.close();
    await _hostKey.close();
    await _transfers.close();
    await _connectErrors.close();
    _fromWorker.close();
  }
}

class SftpService {
  Future<SftpSession> connect(SshConnectParams params) async {
    final fromWorker = ReceivePort();
    final stream = fromWorker.asBroadcastStream();
    final handshake = Completer<SendPort>();
    final sub = stream.listen((msg) {
      if (msg is SendPort && !handshake.isCompleted) handshake.complete(msg);
    });
    try {
      await Isolate.spawn(sftpWorkerMain, fromWorker.sendPort);
      final toWorker =
          await handshake.future.timeout(const Duration(seconds: 10));
      await sub.cancel();
      final session = SftpSession.fromStream(toWorker, fromWorker, stream);
      toWorker.send(SftpConnect(params));
      return session;
    } catch (_) {
      await sub.cancel();
      fromWorker.close();
      rethrow;
    }
  }
}
