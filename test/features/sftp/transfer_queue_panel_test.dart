import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/transfer_queue_panel.dart';
import 'package:sshall/services/sftp/transfer_queue.dart';
import 'package:sshall/theme/app_colors.dart';

TransferJob _job({
  required int id,
  required String name,
  required JobStatus status,
  int size = 10,
  int bytes = 0,
  String? error,
}) => TransferJob(
  id: id,
  batchId: 'b1',
  kind: TransferKind.download,
  srcPath: '/s/$name',
  destPath: '/d/$name',
  name: name,
  size: size,
  status: status,
  bytes: bytes,
  error: error,
);

BatchView _batch({
  required String id,
  required String name,
  bool scanning = false,
  int total = 2,
  int done = 0,
  int failed = 0,
  int active = 0,
  int queued = 0,
  int bytes = 0,
  int totalBytes = 20,
}) => BatchView(
  id: id,
  name: name,
  scanning: scanning,
  total: total,
  done: done,
  failed: failed,
  cancelled: 0,
  active: active,
  queued: queued,
  bytes: bytes,
  totalBytes: totalBytes,
);

Future<void> _pump(WidgetTester tester, Widget panel) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: panel),
  ),
);

void main() {
  testWidgets('renders aggregate progress and file count for an active batch', (
    tester,
  ) async {
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [
          _batch(id: 'b1', name: 'docs', active: 1, done: 1, bytes: 15),
        ],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    expect(find.textContaining('docs'), findsOneWidget);
    expect(find.textContaining('1/2'), findsOneWidget); // done/total files
  });

  testWidgets('scanning batch shows the scanning label', (tester) async {
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [_batch(id: 'b1', name: 'docs', scanning: true, total: 0)],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    expect(find.textContaining('Taranıyor'), findsOneWidget);
  });

  testWidgets('cancel button fires onCancelBatch for an in-progress batch', (
    tester,
  ) async {
    String? cancelled;
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [_batch(id: 'b1', name: 'docs', active: 2)],
        onCancelBatch: (id) => cancelled = id,
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    await tester.tap(find.byTooltip('İptal'));
    expect(cancelled, 'b1');
  });

  testWidgets('finished batch shows summary and a remove button', (
    tester,
  ) async {
    String? dismissed;
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [
          _batch(
            id: 'b1',
            name: 'docs',
            total: 3,
            done: 2,
            failed: 1,
            bytes: 20,
          ),
        ],
        onCancelBatch: (_) {},
        onDismissBatch: (id) => dismissed = id,
        onClearFinished: () {},
      ),
    );
    // Summary mentions success + failure counts.
    expect(find.textContaining('2/3'), findsOneWidget);
    expect(find.textContaining('başarısız'), findsOneWidget);
    await tester.tap(find.byTooltip('Kaldır'));
    expect(dismissed, 'b1');
  });

  testWidgets('clear-finished button shows only when a finished batch exists', (
    tester,
  ) async {
    var cleared = false;
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [_batch(id: 'b1', name: 'docs', total: 1, done: 1, bytes: 20)],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () => cleared = true,
      ),
    );
    await tester.tap(find.text('Bitenleri temizle'));
    expect(cleared, isTrue);
  });

  // ---- D7 ----
  testWidgets('cancel (stop_circle) and dismiss (close) are distinct icons', (
    tester,
  ) async {
    // An in-flight batch uses stop_circle for CANCEL.
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [_batch(id: 'b1', name: 'docs', active: 1, total: 2)],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    // A finished batch uses close for DISMISS (no stop_circle).
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [_batch(id: 'b1', name: 'docs', total: 1, done: 1, bytes: 20)],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);
  });

  testWidgets('a batch expands to per-file sub-rows', (tester) async {
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [
          _batch(id: 'b1', name: 'docs', active: 1, queued: 1, total: 2),
        ],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
        jobsFor: (_) => [
          _job(id: 1, name: 'a.txt', status: JobStatus.active, bytes: 5),
          _job(id: 2, name: 'b.txt', status: JobStatus.queued),
        ],
      ),
    );
    // Collapsed: sub-rows not shown yet.
    expect(find.text('a.txt'), findsNothing);
    await tester.tap(find.byKey(const Key('batchExpand_b1')));
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.text('b.txt'), findsOneWidget);
  });

  testWidgets(
    'active batch shows bytes done/total + speed when a rate exists',
    (tester) async {
      await _pump(
        tester,
        TransferQueuePanel(
          batches: [
            _batch(
              id: 'b1',
              name: 'docs',
              active: 1,
              total: 2,
              bytes: 1048576,
              totalBytes: 4194304,
            ),
          ],
          onCancelBatch: (_) {},
          onDismissBatch: (_) {},
          onClearFinished: () {},
          jobsFor: (_) => [
            _job(
              id: 1,
              name: 'a.txt',
              status: JobStatus.active,
              bytes: 1048576,
              size: 4194304,
            ),
          ],
          rateFor: (_) => 2097152, // 2 MB/s
        ),
      );
      // "1.0 MB/4.0 MB · 2.0 MB/s · ~..." appears on the active batch row (the
      // rate also appears in the summary line, so allow more than one).
      expect(find.textContaining('1.0 MB/4.0 MB'), findsOneWidget);
      expect(find.textContaining('2.0 MB/s'), findsWidgets);
    },
  );

  testWidgets('failed batch stays visible with a reason + Yeniden dene', (
    tester,
  ) async {
    String? retried;
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [
          _batch(
            id: 'b1',
            name: 'docs',
            total: 2,
            done: 1,
            failed: 1,
            bytes: 10,
          ),
        ],
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
        onRetryBatch: (id) => retried = id,
        jobsFor: (_) => [
          _job(id: 1, name: 'a.txt', status: JobStatus.done, bytes: 10),
          _job(
            id: 2,
            name: 'b.txt',
            status: JobStatus.failed,
            error: 'izin yok',
          ),
        ],
      ),
    );
    expect(find.byTooltip('Yeniden dene'), findsWidgets);
    await tester.tap(find.byKey(const Key('retryBatch_b1')));
    expect(retried, 'b1');
    // Expand to see the per-file reason + a per-job retry.
    await tester.tap(find.byKey(const Key('batchExpand_b1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('izin yok'), findsOneWidget);
    expect(find.byKey(const Key('retryJob_2')), findsOneWidget);
  });

  testWidgets('summary line + count badge; collapse hides batch detail', (
    tester,
  ) async {
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [
          _batch(id: 'b1', name: 'docs', active: 1, total: 2),
          _batch(id: 'b2', name: 'logs', active: 1, total: 1),
        ],
        collapsed: false,
        onToggleCollapse: () {},
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    // Summary shows the active count.
    expect(find.textContaining('2 aktarım'), findsOneWidget);
    // Count badge.
    expect(find.text('2'), findsOneWidget);
    // Batch rows visible while expanded.
    expect(find.textContaining('docs'), findsOneWidget);
    expect(find.textContaining('logs'), findsOneWidget);
  });

  testWidgets('collapsed panel hides per-batch rows but keeps the summary', (
    tester,
  ) async {
    await _pump(
      tester,
      TransferQueuePanel(
        batches: [_batch(id: 'b1', name: 'docs', active: 1, total: 2)],
        collapsed: true,
        onToggleCollapse: () {},
        onCancelBatch: (_) {},
        onDismissBatch: (_) {},
        onClearFinished: () {},
      ),
    );
    expect(find.textContaining('aktarım'), findsOneWidget); // summary kept
    expect(find.textContaining('docs'), findsNothing); // batch row hidden
  });
}
