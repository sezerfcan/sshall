import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/transfer_plan.dart';
import 'package:sshall/services/sftp/transfer_queue.dart';

/// Records start() calls and hands out sequential worker transfer ids, like the
/// real session's monotonic counter.
class _Starter {
  int _next = 100;
  final List<TransferJob> started = [];
  int call(TransferJob j) {
    started.add(j);
    return _next++;
  }
}

List<FileJob> _files(int n) => List.generate(
  n,
  (i) => FileJob(
    srcPath: '/s/f$i',
    destPath: '/d/f$i',
    name: 'f$i',
    size: 10,
    destExists: false,
  ),
);

void main() {
  test('respects the concurrency cap', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 3);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(5));
    expect(s.started.length, 3); // only 3 dispatched at once
    final v = q.batchView('b1')!;
    expect(v.active, 3);
    expect(v.queued, 2);
  });

  test('a done event pumps the next queued job (FIFO)', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 1);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(2));
    expect(s.started.map((j) => j.name), ['f0']);
    final tid = s.started.first.transferId!;
    q.onEvent(TransferDone(tid, '/d/f0'));
    expect(s.started.map((j) => j.name), ['f0', 'f1']); // next started
    expect(q.batchView('b1')!.done, 1);
  });

  test('a failed job does not stop the batch (continue-on-error)', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 1);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(2));
    q.onEvent(TransferFailed(s.started.first.transferId!, 'izin yok'));
    expect(s.started.length, 2); // second still started despite first failing
    final v = q.batchView('b1')!;
    expect(v.failed, 1);
  });

  test('progress updates aggregate bytes', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 2);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(2));
    q.onEvent(TransferProgress(s.started[0].transferId!, 4, 10));
    q.onEvent(TransferProgress(s.started[1].transferId!, 6, 10));
    final v = q.batchView('b1')!;
    expect(v.bytes, 10);
    expect(v.totalBytes, 20);
    expect(v.fraction, closeTo(0.5, 1e-9));
  });

  test('cancel a queued job marks it cancelled and never starts it', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 1);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(2));
    // f1 is queued (id is the 2nd job). Find its job id.
    final queuedJobId = q.jobsForTest('b1')[1].id;
    q.cancelJob(queuedJobId);
    expect(s.started.length, 1); // f1 never dispatched
    expect(q.batchView('b1')!.cancelled, 1);
  });

  test(
    'cancel an active job calls cancel(transferId) and ignores its later failure',
    () {
      final s = _Starter();
      final cancelled = <int>[];
      final q = TransferQueue(
        start: s.call,
        cancel: cancelled.add,
        concurrency: 1,
      );
      q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(1));
      final tid = s.started.first.transferId!;
      final jobId = q.jobsForTest('b1').first.id;
      q.cancelJob(jobId);
      expect(cancelled, [tid]);
      // Worker still emits a cancellation failure; queue keeps it cancelled.
      q.onEvent(TransferFailed(tid, 'İptal edildi'));
      expect(q.batchView('b1')!.cancelled, 1);
      expect(q.batchView('b1')!.failed, 0);
    },
  );

  test('unknown transfer id is swallowed', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 1);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(1));
    expect(() => q.onEvent(TransferDone(999999, '/x')), returnsNormally);
  });

  test('beginBatch shows scanning, enqueueBatch clears it', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 3);
    q.beginBatch('b1', 'docs');
    expect(q.batchView('b1')!.scanning, isTrue);
    q.enqueueBatch('b1', 'docs', TransferKind.upload, _files(1));
    expect(q.batchView('b1')!.scanning, isFalse);
  });

  test('a fully-skipped (empty) batch is finished and dismissable', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 3);
    q.beginBatch('b1', 'docs');
    // Every file was skipped by the policy -> enqueue with no jobs.
    q.enqueueBatch('b1', 'docs', TransferKind.upload, const <FileJob>[]);
    expect(s.started, isEmpty);
    expect(q.isBatchFinished('b1'), isTrue);
    expect(q.batchView('b1')!.finished, isTrue);
    q.dismissBatch('b1');
    expect(q.batchView('b1'), isNull);
  });

  test('retryJob re-queues a failed job and pumps it (D7)', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 1);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(1));
    final tid = s.started.first.transferId!;
    final jobId = q.jobsFor('b1').first.id;
    q.onEvent(TransferFailed(tid, 'izin yok'));
    expect(q.batchView('b1')!.failed, 1);
    q.retryJob(jobId);
    // The failed job is queued again and re-dispatched (start called twice).
    expect(s.started.length, 2);
    final v = q.batchView('b1')!;
    expect(v.failed, 0);
    expect(v.active, 1);
    expect(q.jobsFor('b1').first.error, isNull);
  });

  test('retryJob is a no-op for a done job', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 1);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(1));
    final jobId = q.jobsFor('b1').first.id;
    q.onEvent(TransferDone(s.started.first.transferId!, '/d/f0'));
    q.retryJob(jobId);
    expect(s.started.length, 1); // not restarted
    expect(q.batchView('b1')!.done, 1);
  });

  test(
    'retryFailedBatch re-queues only failed jobs, leaving done untouched',
    () {
      final s = _Starter();
      final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 2);
      q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(2));
      final t0 = s.started[0].transferId!;
      final t1 = s.started[1].transferId!;
      q.onEvent(TransferDone(t0, '/d/f0')); // f0 done
      q.onEvent(TransferFailed(t1, 'izin yok')); // f1 failed
      expect(q.batchView('b1')!.done, 1);
      expect(q.batchView('b1')!.failed, 1);
      q.retryFailedBatch('b1');
      final v = q.batchView('b1')!;
      expect(v.done, 1); // f0 untouched
      expect(v.failed, 0); // f1 re-queued
      expect(v.active, 1); // f1 re-dispatched
      expect(s.started.length, 3); // f0, f1, then f1 again
    },
  );

  test('isBatchFinished and dismiss/clearFinished', () {
    final s = _Starter();
    final q = TransferQueue(start: s.call, cancel: (_) {}, concurrency: 3);
    q.enqueueBatch('b1', 'batch', TransferKind.upload, _files(1));
    expect(q.isBatchFinished('b1'), isFalse);
    q.onEvent(TransferDone(s.started.first.transferId!, '/d/f0'));
    expect(q.isBatchFinished('b1'), isTrue);
    q.dismissBatch('b1');
    expect(q.batchView('b1'), isNull);
  });
}
