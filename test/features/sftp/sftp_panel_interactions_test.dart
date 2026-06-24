import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/data/models/remote_entry.dart';
import 'package:sshall/features/sftp/file_pane.dart';
import 'package:sshall/features/sftp/sftp_providers.dart';
import 'package:sshall/features/sftp/sftp_view.dart';
import 'package:sshall/features/shell/resizable_split.dart';
import 'package:sshall/services/sftp/remote_file_ops.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart' show sharedPrefsProvider;

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getDownloadsPath() async => dir;
}

/// Backend-agnostic fake (a DockerFileBackend-shaped RemoteFileOps): the same
/// SFTP view drives it through the RemoteFileOps interface only (ADR 0028).
class _FakeRemoteFileOps implements RemoteFileOps {
  final _controller = StreamController<SftpEvent>.broadcast();
  final List<RemoteEntry> entries;
  final List<({String src, String dest, bool upload})> transfersStarted = [];
  int _nextId = 1;
  _FakeRemoteFileOps(this.entries);

  @override
  Future<List<RemoteEntry>> list(String path) async => entries;
  @override
  Future<RemoteEntry?> stat(String path) async => null;
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> rename(String from, String to) async {}
  @override
  Future<void> remove(String path, {required bool isDir}) async {}
  @override
  Future<void> chmod(String path, int mode) async {}
  @override
  int startDownload(String remotePath, String localFinalPath) {
    transfersStarted.add((
      src: remotePath,
      dest: localFinalPath,
      upload: false,
    ));
    return _nextId++;
  }

  @override
  int startUpload(String localPath, String remoteFinalPath) {
    transfersStarted.add((src: localPath, dest: remoteFinalPath, upload: true));
    return _nextId++;
  }

  @override
  void cancel(int transferId) {}
  @override
  Stream<SftpEvent> get transfers => _controller.stream;
  @override
  Future<void> close() async => _controller.close();
}

RemoteEntry _re(String name, {bool dir = false, int size = 0, int? mode}) =>
    RemoteEntry(
      name: name,
      path: './$name',
      isDir: dir,
      isSymlink: false,
      size: size,
      modified: null,
      mode: mode,
    );

Future<void> _mountView(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required _FakeRemoteFileOps backend,
  Size size = const Size(1000, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
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
  container.read(sftpSessionProvider.notifier).state = backend;
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sshall_panel_ix');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<SharedPreferences> freshPrefs([Map<String, Object> seed = const {}]) {
    SharedPreferences.setMockInitialValues(seed);
    return SharedPreferences.getInstance();
  }

  testWidgets(
    'D1: panes render in a horizontal ResizableSplit, weight persists',
    (tester) async {
      final prefs = await freshPrefs();
      final backend = _FakeRemoteFileOps([_re('container_file.txt')]);
      addTearDown(backend.close);
      await _mountView(tester, prefs: prefs, backend: backend);

      // The fixed Expanded/Expanded Row is gone — a horizontal ResizableSplit
      // hosts the two panes (YEREL left, UZAK right).
      expect(find.byType(ResizableSplit), findsOneWidget);
      final split = tester.widget<ResizableSplit>(find.byType(ResizableSplit));
      expect(split.axis, Axis.horizontal);
      expect(find.text('YEREL'), findsOneWidget);
      expect(find.text('UZAK'), findsOneWidget);

      // Persisting a new weight writes it to prefs and re-mount restores it.
      split.onWeights([0.7, 0.3]);
      await tester.pump();
      expect(prefs.getStringList('sftpPaneWeights'), isNotNull);
      final saved = prefs
          .getStringList('sftpPaneWeights')!
          .map(double.parse)
          .toList();
      expect(saved[0], closeTo(0.7, 1e-6));
    },
  );

  testWidgets('D1: persisted weight is applied on mount', (tester) async {
    final prefs = await freshPrefs({
      'sftpPaneWeights': ['0.65', '0.35'],
    });
    final backend = _FakeRemoteFileOps([_re('x.txt')]);
    addTearDown(backend.close);
    await _mountView(tester, prefs: prefs, backend: backend);
    final split = tester.widget<ResizableSplit>(find.byType(ResizableSplit));
    expect(split.weights[0], closeTo(0.65, 1e-6));
  });

  testWidgets('D3: clicking a remote column header sorts + persists per pane', (
    tester,
  ) async {
    final prefs = await freshPrefs();
    final backend = _FakeRemoteFileOps([
      _re('big.bin', size: 3000),
      _re('small.txt', size: 10),
    ]);
    addTearDown(backend.close);
    await _mountView(tester, prefs: prefs, backend: backend);

    // The remote pane (showPermissions) is the one with an "İzinler" header.
    // Tap its "Boyut" header to sort by size ascending: small.txt before big.bin.
    final sizeHeaders = find.byKey(const Key('sortHeader_size'));
    expect(sizeHeaders, findsNWidgets(2)); // local + remote
    await tester.tap(sizeHeaders.last); // remote pane
    await tester.pumpAndSettle();

    final ySmall = tester.getTopLeft(find.text('small.txt')).dy;
    final yBig = tester.getTopLeft(find.text('big.bin')).dy;
    expect(ySmall, lessThan(yBig));

    // Sort persisted for the remote pane.
    expect(prefs.getString('sftpRemoteSort'), 'size:asc');
  });

  testWidgets('D4/D5: a remote-sourced drop on the local pane starts a download', (
    tester,
  ) async {
    final prefs = await freshPrefs();
    final dragged = _re('drag_me.txt', size: 5);
    final backend = _FakeRemoteFileOps([dragged]);
    addTearDown(backend.close);
    await _mountView(tester, prefs: prefs, backend: backend);

    // Find the LOCAL pane (the one with a "Klasör seç" affordance / not remote)
    // and invoke its drop handler with a payload sourced from the remote pane.
    // This exercises the view's _onDrop → _transferEntry(download) wiring; the
    // gesture-level drag is covered in file_pane_test.
    final panes = tester.widgetList<FilePane>(find.byType(FilePane)).toList();
    final localPane = panes.firstWhere((p) => !p.isRemote);
    localPane.onDropEntries!(
      FileDragData(entries: [dragged], fromRemote: true),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    // A download (remote→local) was started by the queue.
    expect(backend.transfersStarted, isNotEmpty);
    expect(backend.transfersStarted.first.upload, isFalse);
    expect(backend.transfersStarted.first.src, './drag_me.txt');
  });

  testWidgets('D4: double-click on a remote file transfers it to local', (
    tester,
  ) async {
    final prefs = await freshPrefs();
    final backend = _FakeRemoteFileOps([_re('dbl.txt', size: 9)]);
    addTearDown(backend.close);
    await _mountView(tester, prefs: prefs, backend: backend);

    final row = find.text('dbl.txt');
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(backend.transfersStarted, isNotEmpty);
    expect(backend.transfersStarted.first.upload, isFalse);
  });

  testWidgets('§9: the SFTP help dialog opens from the header help button', (
    tester,
  ) async {
    final prefs = await freshPrefs();
    final backend = _FakeRemoteFileOps([_re('a.txt')]);
    addTearDown(backend.close);
    await _mountView(tester, prefs: prefs, backend: backend);
    await tester.tap(find.byKey(const Key('sftpHelpButton')));
    await tester.pumpAndSettle();
    expect(find.text('SFTP yardımı'), findsWidgets);
    expect(find.textContaining('Sürükle-bırak'), findsOneWidget);
  });
}
