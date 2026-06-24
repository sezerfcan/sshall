import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/docker/docker_providers.dart';
import 'package:sshall/features/shell/connection_sidebar.dart';
import 'package:sshall/services/docker/docker_host.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Connection _conn(String id, String label) => Connection(
    id: id, label: label, host: 'h', folderId: null,
    username: null, port: null, authRef: null, tags: const [], order: 0,
    docker: false);

/// An unlocked store with one plain (non-Docker) root host so the connections
/// tree renders something while we exercise the always-visible Local Docker node.
Future<SecureStore> _seededStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate((d) => VaultData(
        connections: [_conn('laptop', 'laptop')],
        folders: const [],
        identities: d.identities,
        pins: d.pins,
      ));
  return store;
}

DockerContainer _runningApi() => const DockerContainer(
      id: 'api123',
      name: 'api',
      image: 'api:latest',
      state: 'running',
      status: 'Up 2 minutes',
      ports: [],
    );

Future<ProviderContainer> _pumpSidebar(
  WidgetTester tester, {
  required SecureStore store,
  required SharedPreferences prefs,
  required Override localOverride,
}) async {
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    secureStoreProvider.overrideWith((ref) async => store),
    localOverride,
  ]);
  await tester.runAsync(() => container.read(secureStoreProvider.future));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: appThemeData(AppThemeId.night),
      home: Scaffold(
        body: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  testWidgets('always-visible Local Docker node expands to show containers',
      (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_localdocker'));
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => _seededStore(tmp));

    final container = await _pumpSidebar(
      tester,
      store: store!,
      prefs: prefs,
      localOverride:
          localContainerListProvider.overrideWith((ref) async => [_runningApi()]),
    );

    // Node is always present, collapsed by default (container hidden).
    expect(find.byKey(const Key('local-docker-node')), findsOneWidget);
    expect(find.text('Local Docker'), findsOneWidget);
    expect(find.text('api'), findsNothing);

    // Tapping the node expands it and renders the 'api' container row.
    await tester.tap(find.byKey(const Key('local-docker-node')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('api'), findsOneWidget);

    // Detach the sidebar before tearing down the container so no disposed
    // element tree gets a transient layout pass during dispose.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('Local Docker node surfaces a daemon-not-running error on expand',
      (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_localdocker'));
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => _seededStore(tmp));

    final container = await _pumpSidebar(
      tester,
      store: store!,
      prefs: prefs,
      localOverride: localContainerListProvider.overrideWith(
        (ref) async =>
            throw DockerException(DockerErrorKind.daemonNotRunning, ''),
      ),
    );

    await tester.tap(find.byKey(const Key('local-docker-node')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Docker çalışmıyor — Docker Desktop\'ı başlatın'),
        findsOneWidget);

    // Detach the sidebar before tearing down the container so no disposed
    // element tree gets a transient layout pass during dispose.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
