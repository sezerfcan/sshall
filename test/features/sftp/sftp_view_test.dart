import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sshall/data/models/remote_entry.dart';
import 'package:sshall/features/sftp/file_opener.dart';
import 'package:sshall/features/sftp/local_file_probe.dart';
import 'package:sshall/features/sftp/remote_edit_panel.dart';
import 'package:sshall/features/sftp/sftp_providers.dart';
import 'package:sshall/features/sftp/sftp_view.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/services/sftp/sftp_service.dart';
import 'package:sshall/theme/app_colors.dart';

/// Answers the docs-dir lookup that [SftpView]'s `_bootstrap` performs, so the
/// local pane doesn't error out. Same approach as app_shell_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Records open requests and pretends the OS accepted them, so the edit flow
/// reaches the "watching" state without touching a real editor.
class _RecordingFileOpener implements FileOpener {
  final opened = <String>[];
  @override
  Future<bool> open(String path) async {
    opened.add(path);
    return true;
  }
}

/// In-memory probe: ensureDir/deleteDir are no-ops and stat reports nothing,
/// so the edit flow runs without touching the real filesystem.
class _FakeLocalFileProbe implements LocalFileProbe {
  @override
  Future<({int mtimeMs, int size})?> stat(String path) async => null;
  @override
  Future<void> ensureDir(String dirPath) async {}
  @override
  Future<void> deleteDir(String dirPath) async {}
  @override
  Future<List<String>> childDirs(String rootPath) async => const [];
}

void main() {
  testWidgets('shows empty state with help when no session', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SftpView()),
        ),
      ),
    );
    expect(find.textContaining('SFTP açın'), findsOneWidget);
  });

  testWidgets('on session change loads remote pane and subscribes to transfers', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sftp_view'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    // Fake worker: the session sends RPCs to [workerInbox] and listens on
    // [fromWorker]. We reply to ListDir with one entry, and we also keep
    // [fromWorker] so the test can push transfer events onto the session.
    final workerInbox = ReceivePort();
    final fromWorker = ReceivePort();
    addTearDown(workerInbox.close);
    addTearDown(fromWorker.close);

    workerInbox.listen((cmd) {
      if (cmd is SftpRpc && cmd.op is ListDir) {
        fromWorker.sendPort.send(
          SftpReply.ok(cmd.id, const <RemoteEntry>[
            RemoteEntry(
              name: 'remote_file.txt',
              path: './remote_file.txt',
              isDir: false,
              isSymlink: false,
              size: 42,
              modified: null,
              mode: null,
            ),
          ]),
        );
      }
    });

    final session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SftpView()),
        ),
      ),
    );
    // Mount with null session: empty state, _bootstrap runs (post-frame).
    await tester.pump();
    expect(find.textContaining('SFTP açın'), findsOneWidget);

    // Now a host is opened -> a real session appears. This is the seam: the
    // ref.listen hook must call _attachSession on the change. The list() RPC
    // and stream events travel over real ReceivePorts, so let the real event
    // loop run via runAsync, then pump to flush the resulting setState.
    container.read(sftpSessionProvider.notifier).state = session;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();

    // Remote pane populated -> proves _refreshRemote ran on session change.
    expect(find.text('remote_file.txt'), findsOneWidget);

    // Drive a real single-file download so the queue learns the worker transfer
    // id. _transferFile checks the LOCAL fs for a conflict (the file is absent
    // in tmp), enqueues a batch, and the queue pumps -> startDownload(id=1).
    // The remote pane's inline "Yerele aktar" action transfers it to local.
    await tester.tap(find.byTooltip('Yerele aktar'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // Panel renders the in-progress batch -> the queue received the enqueue.
    expect(find.textContaining('remote_file.txt'), findsWidgets);

    // Push a terminal TransferDone for that worker id. If the view re-subscribed
    // in _attachSession, _onTransfer fires, advances the queue, and the one-time
    // summary SnackBar appears -> proves the subscription seam is intact.
    fromWorker.sendPort.send(TransferDone(1, './remote_file.txt'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
    // The one-time summary SnackBar uses "name: ..." (distinct from the panel
    // row's "name — ..."), so this matches only the SnackBar.
    expect(find.text('remote_file.txt: 1/1 başarılı'), findsOneWidget);

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('per-job rate meter is pruned when its batch is dismissed', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sftp_meter_prune'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    final workerInbox = ReceivePort();
    final fromWorker = ReceivePort();
    addTearDown(workerInbox.close);
    addTearDown(fromWorker.close);
    workerInbox.listen((cmd) {
      if (cmd is SftpRpc && cmd.op is ListDir) {
        fromWorker.sendPort.send(
          SftpReply.ok(cmd.id, const <RemoteEntry>[
            RemoteEntry(
              name: 'remote_file.txt',
              path: './remote_file.txt',
              isDir: false,
              isSymlink: false,
              size: 100,
              modified: null,
              mode: null,
            ),
          ]),
        );
      }
    });

    final session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SftpView()),
        ),
      ),
    );
    await tester.pump();
    container.read(sftpSessionProvider.notifier).state = session;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();

    expect(find.text('remote_file.txt'), findsOneWidget);

    // Reach the view state to observe the private meter map via the test seam.
    final state = tester.state(find.byType(SftpView)) as dynamic;
    expect(state.meterCount, 0);

    // Start a real download (queue dispatches startDownload -> worker id 1).
    await tester.tap(find.byTooltip('Yerele aktar'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // A progress sample creates a per-job rate meter (keyed by the job id).
    fromWorker.sendPort.send(TransferProgress(1, 50, 100));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
    expect(
      state.meterCount,
      1,
      reason: 'a progress sample must create one meter for the active job',
    );

    // Finish the batch so it becomes dismissable.
    fromWorker.sendPort.send(TransferDone(1, './remote_file.txt'));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();

    // Dismiss the finished batch via the panel's "Kaldır" button. Its meter
    // must be pruned, so the map shrinks back to empty.
    await tester.tap(find.byKey(const Key('dismissBatch_b1')));
    await tester.pump();
    expect(
      state.meterCount,
      0,
      reason: 'dismissing a batch must prune its job rate meters',
    );

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('remote mkdir rejects a path-traversal name and sends no RPC', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sftp_traversal'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    // Record every op the worker receives so we can assert no Mkdir is sent.
    final received = <SftpOp>[];
    final workerInbox = ReceivePort();
    final fromWorker = ReceivePort();
    addTearDown(workerInbox.close);
    addTearDown(fromWorker.close);

    workerInbox.listen((cmd) {
      if (cmd is SftpRpc) {
        received.add(cmd.op);
        if (cmd.op is ListDir) {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, const <RemoteEntry>[]));
        } else {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, null));
        }
      }
    });

    final session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SftpView()),
        ),
      ),
    );
    await tester.pump();
    container.read(sftpSessionProvider.notifier).state = session;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();

    received.clear(); // drop the initial ListDir from attaching the session.

    // Open the remote pane's "Yeni klasör" dialog. Both panes expose the same
    // tooltip; the remote pane is the second one in the row.
    final mkdirButtons = find.byTooltip('Yeni klasör');
    expect(mkdirButtons, findsNWidgets(2));
    await tester.tap(mkdirButtons.last);
    await tester.pumpAndSettle();

    // Type a traversal name and confirm.
    await tester.enterText(find.byType(TextField), '../../etc/evil');
    await tester.tap(find.text('Tamam'));
    await tester.pump(); // run the validator + show the SnackBar.

    // The malicious name is rejected: an error is shown and NO Mkdir reached
    // the worker (so nothing escaped the pane).
    expect(find.textContaining('Geçersiz ad'), findsOneWidget);
    expect(received.whereType<Mkdir>(), isEmpty);

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('mkdir prompt shows a hint and errors (not silent) on empty name', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sftp_prompt'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    // The panes only render once a session exists, so attach one (the worker
    // just acks ListDir with an empty listing — same harness as the traversal
    // test above).
    final workerInbox = ReceivePort();
    final fromWorker = ReceivePort();
    addTearDown(workerInbox.close);
    addTearDown(fromWorker.close);
    workerInbox.listen((cmd) {
      if (cmd is SftpRpc) {
        if (cmd.op is ListDir) {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, const <RemoteEntry>[]));
        } else {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, null));
        }
      }
    });
    final session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SftpView()),
        ),
      ),
    );
    await tester.pump();
    container.read(sftpSessionProvider.notifier).state = session;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // Open the local pane's "Yeni klasör" dialog (first of the two panes).
    final mkdirButtons = find.byTooltip('Yeni klasör');
    expect(mkdirButtons, findsNWidgets(2));
    await tester.tap(mkdirButtons.first);
    await tester.pumpAndSettle();

    // The dialog uses the shared AppTextField with a hint, not a bare TextField.
    expect(find.text('örn. yedekler'), findsOneWidget);

    // Confirming with an empty name shows an inline error and KEEPS the dialog
    // open — no more silent close (UX Top-3 #2).
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(find.text('Ad boş olamaz'), findsOneWidget);
    expect(
      find.text('örn. yedekler'),
      findsOneWidget,
      reason: 'dialog must still be open after the empty-name error',
    );

    // Typing clears the inline error.
    await tester.enterText(find.byType(TextField), 'yeni');
    await tester.pumpAndSettle();
    expect(find.text('Ad boş olamaz'), findsNothing);

    // Close without creating.
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('transferring a folder scans, mkdirs, and enqueues its files', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sftp_d2'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    // A local folder "docs" with one file, so the upload walk finds 1 file.
    await tester.runAsync(() async {
      final docs = Directory('${tmp.path}/docs')..createSync();
      File('${docs.path}/a.txt').writeAsStringSync('hello');
    });

    final received = <Object>[];
    final workerInbox = ReceivePort();
    final fromWorker = ReceivePort();
    addTearDown(workerInbox.close);
    addTearDown(fromWorker.close);
    workerInbox.listen((cmd) {
      received.add(cmd);
      if (cmd is SftpRpc) {
        if (cmd.op is ListDir) {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, const <RemoteEntry>[]));
        } else if (cmd.op is StatOp) {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, null)); // dest free
        } else {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, null)); // mkdir etc.
        }
      }
    });

    final session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SftpView()),
        ),
      ),
    );
    await tester.pump();
    container.read(sftpSessionProvider.notifier).state = session;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // Transfer the local "docs" folder via its inline "Uzağa aktar" action.
    await tester.tap(find.byTooltip('Uzağa aktar'));
    await tester.pumpAndSettle();

    // Folder transfer asks the overwrite policy once; choose overwrite.
    expect(find.textContaining('klasörünü aktar'), findsOneWidget);
    await tester.tap(find.text('Üzerine yaz'));
    // Let the scan + mkdir + enqueue round-trips run.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // A Mkdir for the remote "./docs" skeleton and a StartUpload for a.txt
    // reached the worker.
    expect(
      received.whereType<SftpRpc>().where((r) => r.op is Mkdir),
      isNotEmpty,
    );
    expect(received.whereType<SftpStartUpload>(), isNotEmpty);

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('editing a remote file shows a row in the edit panel', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sftp_edit'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    const file = RemoteEntry(
      name: 'remote_file.txt',
      path: './remote_file.txt',
      isDir: false,
      isSymlink: false,
      size: 42,
      modified: null,
      mode: 0x1a4,
    );

    // Fake worker: reply to ListDir (populates the remote pane) AND to StatOp
    // (so RemoteEditController.startEdit's `await stat(...)` completes and the
    // session is added). The subsequent SftpStartDownload is intentionally
    // ignored — no TransferDone is pushed, so the session sits in `downloading`
    // and the panel renders an "İndiriliyor" row for it.
    final workerInbox = ReceivePort();
    final fromWorker = ReceivePort();
    addTearDown(workerInbox.close);
    addTearDown(fromWorker.close);
    workerInbox.listen((cmd) {
      if (cmd is SftpRpc) {
        if (cmd.op is ListDir) {
          fromWorker.sendPort.send(
            SftpReply.ok(cmd.id, const <RemoteEntry>[file]),
          );
        } else if (cmd.op is StatOp) {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, file));
        } else {
          fromWorker.sendPort.send(SftpReply.ok(cmd.id, null));
        }
      }
    });

    final session = SftpSession.fromPorts(workerInbox.sendPort, fromWorker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: Scaffold(
            body: SftpView(
              fileOpener: _RecordingFileOpener(),
              localFileProbe: _FakeLocalFileProbe(),
              editTempRoot: () async => tmp.path,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    container.read(sftpSessionProvider.notifier).state = session;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();

    // Remote pane listed the file.
    expect(find.text('remote_file.txt'), findsOneWidget);

    // The remote file row exposes an inline "Düzenle" action (D4); tap it.
    await tester.tap(find.byTooltip('Düzenle'));
    // Let the StatOp round-trip complete so the session is added.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // The edit panel is present and shows a row for the edited file.
    final panel = find.byType(RemoteEditPanel);
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('remote_file.txt')),
      findsOneWidget,
    );

    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
