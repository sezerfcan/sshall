import 'dart:async';
import 'dart:typed_data';

import 'sftp_messages.dart';

/// Pure, isolate-free core of SFTP file transfer (download/upload).
///
/// The worker isolate (`sftp_worker.dart`) used to own `doDownload`/`doUpload`
/// as closures that directly instantiated `SftpClient`/`dart:io File`, so the
/// `.part`→rename atomicity, cancellation and cleanup logic could only be
/// exercised against a real server (the skipped `sftp_live_test.dart`).
///
/// This class extracts that core verbatim and parameterises its dependencies
/// behind two narrow interfaces ([RemoteFs] + [LocalFs]) and an [emit]
/// callback, so the six critical paths can be unit-tested with fakes — no
/// isolate, no server, deterministic and fast. See ADR 0014.
///
/// The real worker delegates to this engine via production adapters; there is
/// no second, untested copy of the transfer logic.
class SftpTransferEngine {
  SftpTransferEngine({
    required this.remoteFs,
    required this.localFs,
    required this.emit,
    String Function(Object e)? mapErr,
  }) : mapErr = mapErr ?? ((e) => e.toString());

  final RemoteFs remoteFs;
  final LocalFs localFs;
  final void Function(SftpEvent event) emit;

  /// Error formatter. The worker installs an SFTP-aware variant that unwraps
  /// `SftpStatusError.message`; tests/default fall back to `e.toString()`.
  final String Function(Object e) mapErr;

  final Map<int, _Cancel> _transfers = {};

  /// Cancel an in-flight transfer. No-op for unknown ids (already finished).
  void cancel(int transferId) {
    final t = _transfers[transferId];
    if (t != null) {
      t.cancelled = true;
      t.onCancel?.call();
    }
  }

  /// Download [remotePath] to [localFinal], writing to `<localFinal>.part`
  /// first and renaming atomically on success. On cancel/error the `.part`
  /// file is removed and a [TransferFailed] is emitted; [TransferDone] (and the
  /// rename) only happen on the happy path.
  Future<void> download(int tid, String remotePath, String localFinal) async {
    final tmp = '$localFinal.part';
    final token = _Cancel();
    _transfers[tid] = token;
    final out = localFs.openWrite(tmp);
    RemoteReadHandle? file;
    try {
      file = await remoteFs.openRead(remotePath);
      final total = await file.length();
      var done = 0;
      // Subscribe manually (instead of `await for`) so cancellation can tear
      // down the underlying SFTP read stream IMMEDIATELY via sub.cancel(),
      // mirroring the upload path's `writer.abort()`. A plain `await for` only
      // checks the flag between chunks, so on a slow/stalled network the cancel
      // would not take effect until the next chunk arrives (near-infinite wait)
      // and the read stream would stay open holding the remote file handle.
      final completer = Completer<void>();
      final sub = file.read().listen(
        (chunk) {
          out.add(chunk);
          done += chunk.length;
          emit(TransferProgress(tid, done, total));
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      token.onCancel = () {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      };
      await completer.future;
      await out.close();
      await file.close();
      if (token.cancelled) {
        await localFs.delete(tmp).catchError((_) {});
        emit(TransferFailed(tid, 'İptal edildi'));
        return;
      }
      await localFs.rename(tmp, localFinal);
      emit(TransferDone(tid, localFinal));
    } catch (e) {
      await out.close().catchError((_) {});
      await localFs.delete(tmp).catchError((_) {});
      await file?.close();
      emit(TransferFailed(tid, mapErr(e)));
    } finally {
      _transfers.remove(tid);
    }
  }

  /// Upload [localPath] to [remoteFinal], writing to `<remoteFinal>.part`
  /// first and renaming atomically on success. On cancel/error the remote
  /// `.part` file is removed and a [TransferFailed] is emitted.
  Future<void> upload(int tid, String localPath, String remoteFinal) async {
    final tmp = '$remoteFinal.part';
    final token = _Cancel();
    _transfers[tid] = token;
    RemoteWriteHandle? file;
    try {
      final total = await localFs.length(localPath);
      file = await remoteFs.openWrite(tmp);
      final stream = localFs.openRead(localPath).map((b) => Uint8List.fromList(b));
      file.write(stream,
          onProgress: (t) => emit(TransferProgress(tid, t, total)));
      token.onCancel = () => file!.abortWrite();
      await file.writeDone;
      await file.close();
      if (token.cancelled) {
        await remoteFs.remove(tmp).catchError((_) {});
        emit(TransferFailed(tid, 'İptal edildi'));
        return;
      }
      await remoteFs.rename(tmp, remoteFinal);
      emit(TransferDone(tid, remoteFinal));
    } catch (e) {
      await file?.close();
      await remoteFs.remove(tmp).catchError((_) {});
      emit(TransferFailed(tid, mapErr(e)));
    } finally {
      _transfers.remove(tid);
    }
  }
}

class _Cancel {
  bool cancelled = false;
  void Function()? onCancel;
}

/// Narrow remote (SFTP) side the engine needs. Production adapter wraps
/// `SftpClient`; tests provide an in-memory fake.
abstract class RemoteFs {
  Future<RemoteReadHandle> openRead(String path);
  Future<RemoteWriteHandle> openWrite(String path);
  Future<void> remove(String path);
  Future<void> rename(String from, String to);
}

abstract class RemoteReadHandle {
  Future<int?> length();
  Stream<List<int>> read();
  Future<void> close();
}

abstract class RemoteWriteHandle {
  /// Begin streaming [data] to the remote file, reporting cumulative bytes via
  /// [onProgress]. Completion is awaited through [writeDone].
  void write(Stream<Uint8List> data, {required void Function(int) onProgress});
  Future<void> get writeDone;
  void abortWrite();
  Future<void> close();
}

/// Narrow local (`dart:io`) side the engine needs. Production adapter wraps
/// `dart:io File`; tests provide an in-memory fake.
abstract class LocalFs {
  LocalSink openWrite(String path);
  Future<int?> length(String path);
  Future<void> delete(String path);
  Future<void> rename(String from, String to);
  Stream<List<int>> openRead(String path);
}

abstract class LocalSink {
  void add(List<int> data);
  Future<void> close();
}
