import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/connections/connections_view.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

/// Build an unlocked SecureStore backed by a real temp VaultFile, exactly the
/// way secure_store_test.dart does (CryptoService + VaultFile + InMemoryKeyring).
Future<SecureStore> _unlockedStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  return store;
}

void main() {
  testWidgets(
      'shows empty state, then refreshes reactively after store.mutate adds a '
      'connection (no restart)', (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_conn_view'));
    final store = await tester.runAsync(() => _unlockedStore(tmp!));

    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWith((ref) async => store!),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: const Scaffold(body: ConnectionsView()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Empty state: no saved connections yet.
    expect(find.text('Henüz kayıtlı bağlantı yok'), findsOneWidget);

    // Mutate the store to add a real connection — the ListenableBuilder bound
    // to store.revision must rebuild the list WITHOUT a restart (Faz-3 bug).
    await tester.runAsync(() => store!.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
              id: 'c1',
              label: 'prod-box',
              host: 'example.com',
              folderId: null,
              username: 'root',
              port: 22,
              authRef: 'i1',
              tags: [],
              order: 0,
            ),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        )));
    await tester.pump();

    // The new connection is now rendered; the empty state is gone.
    expect(find.text('Henüz kayıtlı bağlantı yok'), findsNothing);
    expect(find.text('prod-box'), findsWidgets);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets(
      'detail card shows inherited folder username and a "miras" marker',
      (tester) async {
    final tmp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sshall_inherit_view')))!;
    final store = await tester.runAsync(() => _unlockedStore(tmp));

    // Folder 'work' supplies username 'deploy' and port 2222; the connection
    // inside it sets neither, so both must resolve via inheritance.
    await tester.runAsync(() => store!.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
              id: 'c1',
              label: 'inherited-box',
              host: 'example.com',
              folderId: 'work',
              username: null,
              port: null,
              authRef: null,
              tags: [],
              order: 0,
            ),
          ],
          folders: [
            ...v.folders,
            const Folder(
              id: 'work',
              parentId: null,
              name: 'work',
              username: 'deploy',
              port: 2222,
              authRef: null,
              order: 0,
            ),
          ],
          identities: v.identities,
          pins: v.pins,
        )));

    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWith((ref) async => store!),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: const Scaffold(body: ConnectionsView()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Select the host so the detail card renders.
    container.read(selectedConnectionProvider.notifier).state =
        store!.snapshot().valueOrNull!.connections.first;
    await tester.pump();

    // Address line reflects the inherited username 'deploy' (host card + detail).
    expect(find.textContaining('deploy@example.com'), findsWidgets);
    // Port inherited from the folder ⇒ a "miras" marker is shown.
    expect(find.textContaining('miras'), findsWidgets);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets(
      'connect is blocked (snackbar, no terminal) when the saved identity is '
      'missing', (tester) async {
    final tmp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sshall_unresolved_view')))!;
    final store = await tester.runAsync(() => _unlockedStore(tmp));

    // Username is set so only the identity is unresolved: authRef points at an
    // id that has no matching Identity (dangling) ⇒ _paramsFor returns null and
    // the connect path must block before ssh.connect (no real SSH needed).
    await tester.runAsync(() => store!.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
              id: 'c1',
              label: 'orphan-box',
              host: 'example.com',
              folderId: null,
              username: 'root',
              port: 22,
              authRef: 'missing-id',
              tags: [],
              order: 0,
            ),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        )));

    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWith((ref) async => store!),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: const Scaffold(body: ConnectionsView()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Select the host so the detail card with the "Bağlan" button renders.
    container.read(selectedConnectionProvider.notifier).state =
        store!.snapshot().valueOrNull!.connections.first;
    await tester.pump();

    // Tap the real "Bağlan" button → drives _connectSaved → _paramsFor == null.
    await tester.tap(find.text('Bağlan'));
    await tester.pump();

    // The block surfaces as a SnackBar and never opens a terminal tab.
    expect(
        find.text('Bu bağlantı için kayıtlı kimlik bulunamadı.'),
        findsOneWidget);
    final tabsState = container.read(tabsControllerProvider);
    expect(tabsState.tabs.values.any((t) => t.kind == TabKind.terminal),
        isFalse);
    expect(tabsState.activeTab?.kind, isNot(TabKind.terminal));

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
