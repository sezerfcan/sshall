import 'package:path/path.dart' as p;

import '../../data/models/remote_entry.dart';
import '../../services/sftp/sftp_messages.dart';
import 'edit_poller.dart';
import 'file_opener.dart';
import 'local_file_probe.dart';
import 'remote_edit_session.dart';

/// Drives remote-edit sessions: download → external editor → poll for saves →
/// conflict-safe auto re-upload. Pure (no Flutter); dependencies injected as
/// closures/seams so it is fully unit-testable (mirrors TransferQueue).
class RemoteEditController {
  RemoteEditController({
    required this.startDownload,
    required this.startUpload,
    required this.stat,
    required this.chmod,
    required this.fileOpener,
    required this.poller,
    required this.probe,
    required this.tempRootPath,
    required this.onChanged,
    String Function()? newId,
    this.pollInterval = const Duration(milliseconds: 1500),
  }) : _newId = newId ?? _defaultIdGen();

  final int Function(String remote, String localTemp) startDownload;
  final int Function(String localTemp, String remote) startUpload;
  final Future<RemoteEntry?> Function(String remote) stat;
  final Future<void> Function(String remote, int mode) chmod;
  final FileOpener fileOpener;
  final EditPoller poller;
  final LocalFileProbe probe;
  final Future<String> Function() tempRootPath;
  final void Function() onChanged;
  final Duration pollInterval;
  final String Function() _newId;

  static String Function() _defaultIdGen() {
    var n = 0;
    return () => 'e${++n}';
  }

  final List<RemoteEditSession> _sessions = [];
  final Map<int, String> _byDownload = {}; // transferId -> sessionId
  final Map<int, String> _byUpload = {};
  // local stat being uploaded, applied to lastLocal on upload-done
  final Map<String, ({int mtimeMs, int size})> _pendingLocalStat = {};

  List<RemoteEditSession> get sessions => List.unmodifiable(_sessions);

  RemoteEditSession? _find(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _replace(RemoteEditSession s) {
    final i = _sessions.indexWhere((e) => e.id == s.id);
    if (i >= 0) _sessions[i] = s;
    onChanged();
  }

  Future<void> startEdit(RemoteEntry file) async {
    final id = _newId();
    final root = await tempRootPath();
    final dir = p.join(root, id);
    final temp = p.join(dir, file.name);
    await probe.ensureDir(dir);

    final base = await stat(file.path);
    final session = RemoteEditSession(
      id: id,
      remotePath: file.path,
      localTempPath: temp,
      baseMtimeMs: base?.modified?.millisecondsSinceEpoch,
      baseSize: base?.size ?? 0,
      mode: base?.mode,
      lastLocalMtimeMs: null,
      lastLocalSize: 0,
      status: RemoteEditStatus.downloading,
      message: null,
    );
    _sessions.add(session);
    onChanged();

    final tid = startDownload(file.path, temp);
    _byDownload[tid] = id;
  }

  void onTransferEvent(SftpEvent e) {
    if (e is TransferDone) {
      final dl = _byDownload.remove(e.transferId);
      if (dl != null) {
        _onDownloadDone(dl);
        return;
      }
      final ul = _byUpload.remove(e.transferId);
      if (ul != null) _onUploadDone(ul);
    } else if (e is TransferFailed) {
      final dl = _byDownload.remove(e.transferId);
      if (dl != null) {
        _setStatus(dl, RemoteEditStatus.error, 'İndirme başarısız: ${e.message}');
        return;
      }
      final ul = _byUpload.remove(e.transferId);
      if (ul != null) {
        _pendingLocalStat.remove(ul);
        _setStatus(ul, RemoteEditStatus.error, 'Yükleme başarısız: ${e.message}');
      }
    }
    // TransferProgress: ignored (edit-back is small; queue shows no progress).
  }

  void _setStatus(String id, RemoteEditStatus status, String? message) {
    final s = _find(id);
    if (s == null) return;
    _replace(s.copyWith(status: status, message: message ?? s.message));
  }

  Future<void> _onDownloadDone(String id) async {
    var s = _find(id);
    if (s == null) return;
    final local = await probe.stat(s.localTempPath);
    if (_find(id) == null) return; // session finished during stat
    final opened = await fileOpener.open(s.localTempPath);
    s = _find(id);
    if (s == null) return; // session finished during open
    if (!opened) {
      _replace(s.copyWith(
        status: RemoteEditStatus.error,
        message: 'Dosya açılamadı — bu tür için varsayılan uygulama yok.',
      ));
      return;
    }
    _replace(s.copyWith(
      status: RemoteEditStatus.watching,
      lastLocalMtimeMs: local?.mtimeMs,
      lastLocalSize: local?.size ?? 0,
    ));
    _ensurePolling();
  }

  Future<void> _onUploadDone(String id) async {
    final s = _find(id);
    if (s == null) return;
    if (s.mode != null) {
      await chmod(s.remotePath, s.mode!);
    }
    final remote = await stat(s.remotePath);
    final local = _pendingLocalStat.remove(id);
    final cur = _find(id);
    if (cur == null) return; // session finished during upload finalize
    _replace(cur.copyWith(
      status: RemoteEditStatus.watching,
      baseMtimeMs: remote?.modified?.millisecondsSinceEpoch,
      baseSize: remote?.size ?? 0,
      lastLocalMtimeMs: local?.mtimeMs,
      lastLocalSize: local?.size ?? cur.lastLocalSize,
    ));
  }

  void onPollTick() {
    for (final s in List<RemoteEditSession>.from(_sessions)) {
      if (s.status != RemoteEditStatus.watching) continue;
      _checkAndUpload(s);
    }
  }

  Future<void> _checkAndUpload(RemoteEditSession s) async {
    final local = await probe.stat(s.localTempPath);
    if (local == null) return;
    final changed =
        local.mtimeMs != s.lastLocalMtimeMs || local.size != s.lastLocalSize;
    if (!changed) return;
    await _uploadBack(s, local, force: false);
  }

  Future<void> _uploadBack(
    RemoteEditSession s,
    ({int mtimeMs, int size}) local, {
    required bool force,
  }) async {
    // mark uploading first so a later tick won't double-fire
    _replace(s.copyWith(status: RemoteEditStatus.uploading));
    if (!force) {
      final remote = await stat(s.remotePath);
      final rMtime = remote?.modified?.millisecondsSinceEpoch;
      final rSize = remote?.size ?? 0;
      if (rMtime != s.baseMtimeMs || rSize != s.baseSize) {
        _replace(s.copyWith(
          status: RemoteEditStatus.conflict,
          message: 'Uzaktaki dosya değişti — yükleme bekletildi.',
        ));
        return;
      }
    }
    _pendingLocalStat[s.id] = local;
    final tid = startUpload(s.localTempPath, s.remotePath);
    _byUpload[tid] = s.id;
  }

  Future<void> resolveConflict(String id, ConflictChoice choice) async {
    final s = _find(id);
    if (s == null || s.status != RemoteEditStatus.conflict) return;
    switch (choice) {
      case ConflictChoice.overwriteRemote:
        final local = await probe.stat(s.localTempPath);
        if (local == null) return;
        await _uploadBack(s, local, force: true);
      case ConflictChoice.keepEditing:
        _replace(s.copyWith(status: RemoteEditStatus.watching));
      case ConflictChoice.saveAsLocal:
        _replace(s.copyWith(
          status: RemoteEditStatus.closedRemote,
          message: 'Yerel kopya korundu: ${s.localTempPath}',
        ));
        _stopPollingIfIdle();
    }
  }

  void _stopPollingIfIdle() {
    final anyWatching =
        _sessions.any((s) => s.status == RemoteEditStatus.watching);
    if (!anyWatching) poller.stop();
  }

  void _ensurePolling() {
    final anyWatching =
        _sessions.any((s) => s.status == RemoteEditStatus.watching);
    if (anyWatching) {
      poller.start(pollInterval, onPollTick);
    }
  }

  Future<void> finish(String id) async {
    final s = _find(id);
    if (s == null) return;
    _sessions.removeWhere((e) => e.id == id);
    _byDownload.removeWhere((_, v) => v == id);
    _byUpload.removeWhere((_, v) => v == id);
    _pendingLocalStat.remove(id);
    onChanged();
    _stopPollingIfIdle();
    // temp dir = parent of the temp file
    await probe.deleteDir(_sessionDir(s));
  }

  void onSftpClosed() {
    poller.stop();
    for (var i = 0; i < _sessions.length; i++) {
      _sessions[i] = _sessions[i].copyWith(
        status: RemoteEditStatus.closedRemote,
        message: 'Bağlantı kapandı — yerel kopya: ${_sessions[i].localTempPath}',
      );
    }
    onChanged();
  }

  Future<void> sweepStaleTempDirs() async {
    if (_sessions.isNotEmpty) return; // never touch dirs with live sessions
    final root = await tempRootPath();
    for (final dir in await probe.childDirs(root)) {
      await probe.deleteDir(dir);
    }
  }

  String _sessionDir(RemoteEditSession s) => p.dirname(s.localTempPath);

  void dispose() => poller.stop();
}
