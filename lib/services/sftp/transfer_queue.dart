import 'sftp_messages.dart';
import 'transfer_plan.dart';

/// Pure, isolate-free transfer queue (D2). Holds transfer jobs grouped into
/// batches (one user action = one batch), dispatches at most [concurrency] at a
/// time through an injected [start] (which returns the worker transfer id), and
/// reacts to transfer events to advance the queue. Continue-on-error: a failed
/// job never blocks the rest. No Flutter/worker — unit-tested. See ADR 0016.
enum TransferKind { upload, download }

enum JobStatus { queued, active, done, failed, cancelled }

class TransferJob {
  final int id; // queue-internal id
  final String batchId;
  final TransferKind kind;
  final String srcPath;
  final String destPath;
  final String name;
  final int size;
  JobStatus status;
  int bytes;
  String? error;
  int? transferId; // worker transfer id while active
  TransferJob({
    required this.id,
    required this.batchId,
    required this.kind,
    required this.srcPath,
    required this.destPath,
    required this.name,
    required this.size,
    this.status = JobStatus.queued,
    this.bytes = 0,
    this.error,
    this.transferId,
  });
}

/// Panel-facing aggregate of one batch.
class BatchView {
  final String id;
  final String name;
  final bool scanning;
  final int total, done, failed, cancelled, active, queued, bytes, totalBytes;
  const BatchView({
    required this.id,
    required this.name,
    required this.scanning,
    required this.total,
    required this.done,
    required this.failed,
    required this.cancelled,
    required this.active,
    required this.queued,
    required this.bytes,
    required this.totalBytes,
  });
  // A batch is finished once scanning is done and nothing is active/queued.
  // This includes a fully-skipped batch (total == 0): with no pending work it
  // must be summarizable and dismissable, not stuck at "0/0 dosya".
  bool get finished => !scanning && active == 0 && queued == 0;
  bool get inProgress => scanning || active > 0 || queued > 0;
  double? get fraction =>
      totalBytes > 0 ? (bytes / totalBytes).clamp(0.0, 1.0) : null;
}

class _Batch {
  final String name;
  bool scanning;
  final List<TransferJob> jobs = [];
  _Batch(this.name, {this.scanning = false});
}

class TransferQueue {
  TransferQueue({
    required this.start,
    required this.cancel,
    this.concurrency = 3,
  });

  final int Function(TransferJob job) start;
  final void Function(int transferId) cancel;
  final int concurrency;

  final Map<String, _Batch> _batches = {}; // insertion-ordered
  final Map<int, TransferJob> _byTransfer = {};
  int _nextJobId = 1;

  Iterable<TransferJob> get _allJobs => _batches.values.expand((b) => b.jobs);

  TransferJob? _job(int id) {
    for (final j in _allJobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  void beginBatch(String batchId, String name) {
    _batches[batchId] = _Batch(name, scanning: true);
  }

  void enqueueBatch(
    String batchId,
    String name,
    TransferKind kind,
    List<FileJob> files,
  ) {
    final b = _batches.putIfAbsent(batchId, () => _Batch(name));
    b.scanning = false;
    for (final f in files) {
      b.jobs.add(
        TransferJob(
          id: _nextJobId++,
          batchId: batchId,
          kind: kind,
          srcPath: f.srcPath,
          destPath: f.destPath,
          name: f.name,
          size: f.size,
        ),
      );
    }
    _pump();
  }

  void _pump() {
    var slots =
        concurrency -
        _allJobs.where((j) => j.status == JobStatus.active).length;
    if (slots <= 0) return;
    for (final j in _allJobs) {
      if (slots <= 0) break;
      if (j.status != JobStatus.queued) continue;
      j.status = JobStatus.active;
      final tid = start(j);
      j.transferId = tid;
      _byTransfer[tid] = j;
      slots--;
    }
  }

  void onEvent(SftpEvent e) {
    int? tid;
    if (e is TransferProgress) {
      tid = e.transferId;
    } else if (e is TransferDone) {
      tid = e.transferId;
    } else if (e is TransferFailed) {
      tid = e.transferId;
    }
    if (tid == null) return;
    final j = _byTransfer[tid];
    if (j == null) return; // unknown / already-cancelled — swallow
    if (e is TransferProgress) {
      j.bytes = e.bytes;
    } else if (e is TransferDone) {
      _byTransfer.remove(tid);
      j.status = JobStatus.done;
      j.bytes = j.size;
      _pump();
    } else if (e is TransferFailed) {
      _byTransfer.remove(tid);
      if (j.status == JobStatus.cancelled) {
        _pump(); // user-cancelled: keep the cancelled status, just advance
        return;
      }
      j.status = JobStatus.failed;
      j.error = e.message;
      _pump();
    }
  }

  void cancelJob(int jobId) {
    final j = _job(jobId);
    if (j == null) return;
    if (j.status == JobStatus.queued) {
      j.status = JobStatus.cancelled;
    } else if (j.status == JobStatus.active) {
      j.status = JobStatus.cancelled;
      final tid = j.transferId;
      if (tid != null) cancel(tid);
    }
    _pump();
  }

  void cancelBatch(String batchId) {
    final b = _batches[batchId];
    if (b == null) return;
    for (final j in [...b.jobs]) {
      if (j.status == JobStatus.queued) {
        j.status = JobStatus.cancelled;
      } else if (j.status == JobStatus.active) {
        j.status = JobStatus.cancelled;
        final tid = j.transferId;
        if (tid != null) cancel(tid);
      }
    }
    _pump();
  }

  /// Re-queue a single failed (or cancelled) job so it is retried (D7). Resets
  /// its byte counter and error, returns it to [JobStatus.queued], and pumps so
  /// it starts again under the existing concurrency cap. No-op for jobs that are
  /// active, done, or queued. The core dispatch/event logic is unchanged — this
  /// only flips one job's status and re-pumps (ADR 0016 preserved).
  void retryJob(int jobId) {
    final j = _job(jobId);
    if (j == null) return;
    if (j.status != JobStatus.failed && j.status != JobStatus.cancelled) return;
    j.status = JobStatus.queued;
    j.bytes = 0;
    j.error = null;
    j.transferId = null;
    _pump();
  }

  /// Re-queue every failed/cancelled job in a batch (D7), leaving done jobs
  /// untouched. Used by the panel's "Yeniden dene" on a failed batch.
  void retryFailedBatch(String batchId) {
    final b = _batches[batchId];
    if (b == null) return;
    for (final j in b.jobs) {
      if (j.status == JobStatus.failed || j.status == JobStatus.cancelled) {
        j.status = JobStatus.queued;
        j.bytes = 0;
        j.error = null;
        j.transferId = null;
      }
    }
    _pump();
  }

  // Matches BatchView.finished: a non-scanning batch with no pending work is
  // finished. `every` is vacuously true on an empty job list, so a fully-skipped
  // batch (no jobs) is finished and can be summarized/dismissed.
  bool _finished(_Batch b) =>
      !b.scanning &&
      b.jobs.every(
        (j) =>
            j.status == JobStatus.done ||
            j.status == JobStatus.failed ||
            j.status == JobStatus.cancelled,
      );

  void dismissBatch(String batchId) {
    final b = _batches[batchId];
    if (b != null && _finished(b)) _batches.remove(batchId);
  }

  void clearFinished() => _batches.removeWhere((_, b) => _finished(b));

  bool isBatchFinished(String batchId) {
    final b = _batches[batchId];
    return b != null && _finished(b);
  }

  BatchView? batchView(String id) {
    final b = _batches[id];
    if (b == null) return null;
    return _view(id, b);
  }

  List<BatchView> get batches =>
      _batches.entries.map((e) => _view(e.key, e.value)).toList();

  BatchView _view(String id, _Batch b) {
    var done = 0, failed = 0, cancelled = 0, active = 0, queued = 0;
    var bytes = 0, totalBytes = 0;
    for (final j in b.jobs) {
      bytes += j.bytes;
      totalBytes += j.size;
      if (j.status == JobStatus.done) {
        done++;
      } else if (j.status == JobStatus.failed) {
        failed++;
      } else if (j.status == JobStatus.cancelled) {
        cancelled++;
      } else if (j.status == JobStatus.active) {
        active++;
      } else {
        queued++;
      }
    }
    return BatchView(
      id: id,
      name: b.name,
      scanning: b.scanning,
      total: b.jobs.length,
      done: done,
      failed: failed,
      cancelled: cancelled,
      active: active,
      queued: queued,
      bytes: bytes,
      totalBytes: totalBytes,
    );
  }

  /// The active job currently bound to [transferId], or null if none. O(1):
  /// reads the same transferId→job index the queue maintains for event routing,
  /// so callers (e.g. the view's rate meters) don't have to scan every batch.
  /// Only active jobs are indexed — a job's entry is dropped once it terminates.
  TransferJob? jobByTransferId(int transferId) => _byTransfer[transferId];

  /// The jobs of a batch in insertion order (D7 — per-file expansion in the
  /// transfer queue panel). Stable, read-only view; the panel renders one
  /// sub-row per job.
  List<TransferJob> jobsFor(String batchId) =>
      List.unmodifiable(_batches[batchId]?.jobs ?? const []);

  /// Test-only alias of [jobsFor] (kept for existing call sites).
  List<TransferJob> jobsForTest(String batchId) => jobsFor(batchId);
}
