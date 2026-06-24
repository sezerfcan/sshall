import 'dart:io';
import 'dart:ui';

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
import 'package:sshall/features/docker/docker_providers.dart';
import 'package:sshall/features/shell/connection_sidebar.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/features/shell/shell_state.dart';
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

Folder _folder(String id, String name) => Folder(
  id: id,
  parentId: null,
  name: name,
  username: null,
  port: null,
  authRef: null,
  order: 0,
);

Connection _conn(
  String id,
  String label, {
  String? folderId,
  bool docker = false,
}) => Connection(
  id: id,
  label: label,
  host: 'h',
  folderId: folderId,
  username: null,
  port: null,
  authRef: null,
  tags: const [],
  order: 0,
  docker: docker,
);

/// Build an unlocked SecureStore backed by a real temp VaultFile + InMemoryKeyring,
/// seeded with one folder ('work') holding a nested host ('web-1') plus a root
/// host ('laptop').
Future<SecureStore> _seededStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate(
    (d) => VaultData(
      connections: [
        _conn('web', 'web-1', folderId: 'work'),
        _conn('laptop', 'laptop'),
      ],
      folders: [_folder('work', 'work')],
      identities: d.identities,
      pins: d.pins,
    ),
  );
  return store;
}

void main() {
  testWidgets('sidebar renders nested tree with expand/collapse', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sidebar'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _seededStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: Scaffold(
            body: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Root host visible; nested host hidden while folder is collapsed.
    expect(find.text('laptop'), findsOneWidget);
    expect(find.text('web-1'), findsNothing);

    // Expand the folder.
    await tester.tap(find.byKey(const Key('folder-work')));
    await tester.pumpAndSettle();

    // Nested host now visible.
    expect(find.text('web-1'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('search filters tree, force-expands matches, shows empty state', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sidebar'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _seededStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: Scaffold(
            body: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Both root and (collapsed) nested hosts exist; nested is hidden initially.
    expect(find.text('laptop'), findsOneWidget);
    expect(find.text('web-1'), findsNothing);

    // Search for the nested host: it should force-expand 'work' and reveal it
    // while filtering out the non-matching root host.
    await tester.enterText(find.byKey(const Key('sidebarSearch')), 'web');
    await tester.pumpAndSettle();
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('laptop'), findsNothing);

    // A query with no matches shows the distinct no-results state (ADR 0035 D2):
    // it echoes the query, names the search scope and offers a one-tap clear.
    await tester.enterText(
      find.byKey(const Key('sidebarSearch')),
      'no-such-host',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar-empty-noresults')), findsOneWidget);
    expect(find.text('"no-such-host" için sonuç yok'), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar-empty-noresults-clear')),
      findsOneWidget,
    );

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('host row exposes an edit/delete context menu', (tester) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sidebar'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _seededStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: Scaffold(
            body: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The row-level kebab (…) menu is revealed on hover/focus (ADR 0030 D6), so
    // hover the row first, then open its menu. 'laptop' is a root-level host; its
    // menu key is 'host-menu-laptop'.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('host-laptop'))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('host-menu-laptop')));
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets(
    'selecting a host highlights its sidebar row with accent text (D5)',
    (tester) async {
      final tmp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('sshall_sidebar'),
      );
      PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final store = await tester.runAsync(() => _seededStore(tmp));

      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          secureStoreProvider.overrideWith((ref) async => store!),
        ],
      );
      await tester.runAsync(() => container.read(secureStoreProvider.future));

      Connection? selected;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appThemeData(AppThemeId.night),
            home: Scaffold(
              body: ConnectionSidebar(
                onSelect: (c) {
                  selected = c;
                  container.read(selectedConnectionProvider.notifier).state = c;
                },
                onNewHost: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final accent = AppColors.night.accent;
      Color labelColor() {
        final w = tester.widget<Text>(find.text('laptop'));
        return w.style!.color!;
      }

      // Before selection: the host label is NOT accent-colored.
      expect(labelColor(), isNot(accent));

      // Tap the host row → it becomes selected and its label turns accent (#1
      // HIGH bug: selection now reflects in the sidebar tree, ADR 0030 D5).
      await tester.tap(find.byKey(const Key('host-laptop')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(selected?.id, 'laptop');
      expect(labelColor(), accent);

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );

  testWidgets('footer Vault button opens the Vault overlay (D9a)', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sidebar'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _seededStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: Scaffold(
            body: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(activeOverlayProvider), ShellOverlay.none);
    // The footer is no longer a dead chip — it is an actionable button.
    await tester.tap(find.byKey(const Key('sidebar-vault-footer')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.vault);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('docker host row shows a Docker marker + expandable Containers node', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_sidebar'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _seededDockerStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
        // Keep the integration deterministic: the node's data path is exercised
        // in containers_node_test; here we only assert the sidebar wiring. Returns
        // synchronously so the FutureProvider resolves to AsyncData immediately.
        containerListProvider('dock').overrideWith((ref) => const []),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: Scaffold(
            body: ConnectionSidebar(onSelect: (_) {}, onNewHost: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Marker (tooltip) + toggle present; node hidden until expanded.
    expect(find.byKey(const Key('docker-toggle-dock')), findsOneWidget);
    expect(find.byTooltip('Docker host'), findsOneWidget);
    expect(find.text('Container yok'), findsNothing);

    // Expand: the Containers node renders (empty -> "Container yok").
    await tester.tap(find.byKey(const Key('docker-toggle-dock')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Container yok'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}

/// Like [_seededStore] but seeds a single Docker-marked root host ('docker-box').
Future<SecureStore> _seededDockerStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate(
    (d) => VaultData(
      connections: [_conn('dock', 'docker-box', docker: true)],
      folders: const [],
      identities: d.identities,
      pins: d.pins,
    ),
  );
  return store;
}
