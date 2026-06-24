import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sshall/data/models/remote_entry.dart';
import 'package:sshall/features/sftp/sftp_providers.dart';
import 'package:sshall/features/sftp/sftp_view.dart';
import 'package:sshall/services/sftp/remote_file_ops.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';
import 'package:sshall/theme/app_colors.dart';

/// Answers the docs-dir lookup that [SftpView]'s `_bootstrap` performs, so the
/// local pane doesn't error out. Same approach as sftp_view_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// A minimal, NON-[SftpSession] [RemoteFileOps] (mimics a [DockerFileBackend]
/// from the view's perspective): the SFTP view consumes only RemoteFileOps
/// members, so this proves the retyped provider (ADR 0028) drives the view with
/// any backend. [list] returns a single entry; [transfers] is an empty
/// broadcast stream.
class _FakeRemoteFileOps implements RemoteFileOps {
  final _controller = StreamController<SftpEvent>.broadcast();
  int listCalls = 0;

  @override
  Future<List<RemoteEntry>> list(String path) async {
    listCalls++;
    return const <RemoteEntry>[
      RemoteEntry(
        name: 'container_file.txt',
        path: './container_file.txt',
        isDir: false,
        isSymlink: false,
        size: 7,
        modified: null,
        mode: null,
      ),
    ];
  }

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
  int startDownload(String remotePath, String localFinalPath) => 1;
  @override
  int startUpload(String localPath, String remoteFinalPath) => 2;
  @override
  void cancel(int transferId) {}
  @override
  Stream<SftpEvent> get transfers => _controller.stream;
  @override
  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  testWidgets(
      'SftpView renders remote entries from a non-SftpSession RemoteFileOps',
      (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_rfo_view'));
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    final backend = _FakeRemoteFileOps();
    addTearDown(backend.close);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: const Scaffold(body: SftpView()),
      ),
    ));
    // Mount with null session: empty state, _bootstrap runs (post-frame).
    await tester.pump();
    expect(find.textContaining('SFTP açın'), findsOneWidget);

    // Publish a backend that is NOT an SftpSession. The ref.listen hook must
    // call _attachSession, which uses only RemoteFileOps members.
    container.read(sftpSessionProvider.notifier).state = backend;
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();

    // The empty-state help is gone and the remote pane shows the backend's
    // entry -> proves the view drives a non-SftpSession backend end to end.
    expect(find.textContaining('SFTP açın'), findsNothing);
    expect(find.text('container_file.txt'), findsOneWidget);
    expect(backend.listCalls, greaterThan(0),
        reason: 'view must call RemoteFileOps.list to populate the remote pane');

    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
