import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/remote_entry.dart';
import 'package:sshall/features/sftp/file_pane.dart';
import 'package:sshall/features/sftp/transfer_queue_panel.dart';
import 'package:sshall/services/sftp/transfer_queue.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

/// Golden coverage for the WinSCP/Transmit-grade SFTP panel (ADR 0037):
///   1. the dual pane (YEREL | UZAK) with breadcrumb + sortable column headers
///      (Ad/Boyut/Değiştirilme/İzinler + a direction triangle) + a selected row,
///   2. a skeleton-loading pane (first-load placeholder rows),
///   3. the transfer queue with an active + a failed batch (per-file expansion,
///      speed/ETA, distinct stop_circle cancel vs close dismiss, failed reason +
///      Yeniden dene, summary),
/// in all three themes (night / day / terminal). Regenerate with:
///   flutter test --update-goldens test/features/sftp/sftp_panel_golden_test.dart
/// then run without the flag to confirm they pass.

const _themes = AppThemeId.values;

RemoteEntry _e(
  String name, {
  bool dir = false,
  int size = 0,
  DateTime? modified,
  int? mode,
}) => RemoteEntry(
  name: name,
  path: '/home/$name',
  isDir: dir,
  isSymlink: false,
  size: size,
  modified: modified,
  mode: mode,
);

final _entries = <FsEntry>[
  _e('logs', dir: true, modified: DateTime(2026, 6, 1, 9, 30), mode: 0x1ED),
  _e(
    'backup.tar.gz',
    size: 4 * 1024 * 1024,
    modified: DateTime(2026, 5, 20, 14, 2),
    mode: 0x1A4,
  ),
  _e(
    'config.yaml',
    size: 2048,
    modified: DateTime(2026, 6, 10, 8, 15),
    mode: 0x1A4,
  ),
  _e(
    'notes.md',
    size: 512,
    modified: DateTime(2026, 6, 22, 18, 45),
    mode: 0x180,
  ),
];

FilePane _pane({
  required String title,
  required bool isRemote,
  Set<String> selected = const {},
  bool loading = false,
  List<FsEntry>? entries,
}) => FilePane(
  title: title,
  path: '/home/user/project',
  entries: entries ?? _entries,
  loading: loading,
  error: null,
  isRemote: isRemote,
  onNavigate: (_) {},
  onUp: () {},
  onRefresh: () {},
  sortColumn: SortColumn.size,
  sortAscending: false,
  onSort: (_) {},
  selectedNames: selected,
  onSelect: (_, {shift = false, meta = false}) {},
  onActivate: (_) {},
  onTransferSelection: (_) {},
  onDropEntries: (_, {targetDir}) {},
  onChooseRoot: isRemote ? null : () {},
  actions: FilePaneActions(
    onOpen: (_) {},
    onTransfer: (_) {},
    onRename: (_) {},
    onDelete: (_) {},
    onMkdir: () {},
    onChmod: isRemote ? (_) {} : null,
    onEdit: isRemote ? (_) {} : null,
  ),
);

TransferJob _job(
  int id,
  String name,
  JobStatus status, {
  int size = 1000,
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

Widget _frame(AppThemeId theme, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: appThemeData(theme),
  home: Scaffold(body: child),
);

void main() {
  for (final theme in _themes) {
    testWidgets(
      'dual pane + breadcrumb + headers + selection — ${theme.name}',
      (tester) async {
        tester.view.physicalSize = const Size(900, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _frame(
            theme,
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: _pane(title: 'YEREL', isRemote: false)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _pane(
                      title: 'UZAK',
                      isRemote: true,
                      selected: {'config.yaml'},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(Row).first,
          matchesGoldenFile('goldens/sftp_dual_pane_${theme.name}.png'),
        );
      },
    );

    testWidgets('skeleton-loading pane — ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(440, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _frame(
          theme,
          Padding(
            padding: const EdgeInsets.all(8),
            child: _pane(
              title: 'UZAK',
              isRemote: true,
              loading: true,
              entries: const [],
            ),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byType(FilePane),
        matchesGoldenFile('goldens/sftp_skeleton_${theme.name}.png'),
      );
    });

    testWidgets('transfer queue — active + failed batch — ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(560, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final jobs = <String, List<TransferJob>>{
        'b1': [
          _job(1, 'a.txt', JobStatus.active, size: 4000, bytes: 1500),
          _job(2, 'b.txt', JobStatus.queued, size: 4000),
        ],
        'b2': [
          _job(3, 'c.bin', JobStatus.done, size: 2000, bytes: 2000),
          _job(4, 'd.bin', JobStatus.failed, error: 'izin reddedildi'),
        ],
      };
      final batches = [
        const BatchView(
          id: 'b1',
          name: 'proje yükle',
          scanning: false,
          total: 2,
          done: 0,
          failed: 0,
          cancelled: 0,
          active: 1,
          queued: 1,
          bytes: 1500,
          totalBytes: 8000,
        ),
        const BatchView(
          id: 'b2',
          name: 'günlükler indir',
          scanning: false,
          total: 2,
          done: 1,
          failed: 1,
          cancelled: 0,
          active: 0,
          queued: 0,
          bytes: 2000,
          totalBytes: 4000,
        ),
      ];

      await tester.pumpWidget(
        _frame(
          theme,
          Align(
            alignment: Alignment.bottomCenter,
            child: TransferQueuePanel(
              batches: batches,
              jobsFor: (id) => jobs[id] ?? const [],
              rateFor: (_) => 2 * 1024 * 1024,
              onCancelBatch: (_) {},
              onDismissBatch: (_) {},
              onClearFinished: () {},
              onRetryBatch: (_) {},
              onRetryJob: (_) {},
              onToggleCollapse: () {},
            ),
          ),
        ),
      );
      // Expand both batches so the per-file sub-rows are visible in the golden.
      await tester.tap(find.byKey(const Key('batchExpand_b1')));
      await tester.tap(find.byKey(const Key('batchExpand_b2')));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(TransferQueuePanel),
        matchesGoldenFile('goldens/sftp_transfer_queue_${theme.name}.png'),
      );
    });
  }
}
