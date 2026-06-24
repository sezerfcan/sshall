import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/connection_sidebar.dart';
import 'package:sshall/features/shell/nav_rail.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

/// Golden coverage for the left navigation (ADR 0030): the rail + the sidebar
/// panel in all three themes, at WIDE (panel expanded) and NARROW (rail-only,
/// panel collapsed) states. Regenerate with:
///   flutter test --update-goldens test/features/shell/sidebar_rail_golden_test.dart
/// then run without the flag to confirm they pass.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Folder _folder(String id, String name) => Folder(
    id: id, parentId: null, name: name,
    username: null, port: null, authRef: null, order: 0);

Connection _conn(String id, String label,
        {String? folderId, bool docker = false}) =>
    Connection(
        id: id, label: label, host: 'h', folderId: folderId,
        username: 'root', port: null, authRef: null, tags: const [], order: 0,
        docker: docker);

Future<SecureStore> _seededStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate((d) => VaultData(
        connections: [
          _conn('web', 'web-1', folderId: 'work'),
          _conn('db', 'db-1', folderId: 'work', docker: true),
          _conn('laptop', 'laptop'),
        ],
        folders: [_folder('work', 'work')],
        identities: d.identities,
        pins: d.pins,
      ));
  return store;
}

const _themes = AppThemeId.values;

void main() {
  for (final theme in _themes) {
    testWidgets('rail golden — ${theme.name} (panel expanded)',
        (tester) async {
      tester.view.physicalSize = const Size(52, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appThemeData(theme),
          home: const Scaffold(body: Row(children: [NavRail()])),
        ),
      ));
      await tester.pump();

      await expectLater(
        find.byType(NavRail),
        matchesGoldenFile('goldens/rail_${theme.name}_expanded.png'),
      );
    });

    testWidgets('rail golden — ${theme.name} (panel collapsed)',
        (tester) async {
      tester.view.physicalSize = const Size(52, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'sidebarCollapsed': true});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      // Sanity: the rail reflects the collapsed (rail-only) state.
      expect(container.read(sidebarVisibleProvider), isFalse);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appThemeData(theme),
          home: const Scaffold(body: Row(children: [NavRail()])),
        ),
      ));
      await tester.pump();

      await expectLater(
        find.byType(NavRail),
        matchesGoldenFile('goldens/rail_${theme.name}_collapsed.png'),
      );
    });

    testWidgets('sidebar golden — ${theme.name} (wide)', (tester) async {
      tester.view.physicalSize = const Size(272, 460);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tmp = await tester
          .runAsync(() => Directory.systemTemp.createTemp('sshall_golden'));
      PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await tester.runAsync(() => _seededStore(tmp));

      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ]);
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(secureStoreProvider.future));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appThemeData(theme),
          home: Scaffold(
            body: SizedBox(
              width: 272,
              child: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Expand the folder so the tree shows nested + a docker host marker.
      await tester.tap(find.byKey(const Key('folder-work')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await expectLater(
        find.byType(ConnectionSidebar),
        matchesGoldenFile('goldens/sidebar_${theme.name}_wide.png'),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => tmp.delete(recursive: true));
    });
  }
}
