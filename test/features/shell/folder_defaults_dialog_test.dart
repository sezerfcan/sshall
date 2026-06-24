import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/folder_defaults_dialog.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

/// Build an unlocked SecureStore backed by a real temp VaultFile + InMemoryKeyring,
/// seeded with a folder 'work' (no defaults) and one identity 'i1'.
Future<SecureStore> _seededStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate((v) => VaultData(
        connections: v.connections,
        folders: const [
          Folder(
            id: 'work',
            parentId: null,
            name: 'work',
            username: null,
            port: null,
            authRef: null,
            order: 0,
          ),
        ],
        identities: const [
          Identity(
            id: 'i1',
            label: 'shared-key',
            type: IdentityType.privateKey,
            secret: 'PEM',
            passphrase: null,
          ),
        ],
        pins: v.pins,
      ));
  return store;
}

/// Build an unlocked store seeded with the given folders + identities.
Future<SecureStore> _customStore(
  Directory dir, {
  required List<Folder> folders,
  required List<Identity> identities,
}) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate((v) => VaultData(
        connections: v.connections,
        folders: folders,
        identities: identities,
        pins: v.pins,
      ));
  return store;
}

/// Pump the folder-defaults dialog for [folderId] over [store] and settle.
Future<ProviderContainer> _openDialog(
  WidgetTester tester,
  SecureStore store,
  String folderId,
) async {
  final container = ProviderContainer(overrides: [
    secureStoreProvider.overrideWith((ref) async => store),
  ]);
  await tester.runAsync(() => container.read(secureStoreProvider.future));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Consumer(builder: (context, ref, _) {
        return ElevatedButton(
          key: const Key('open'),
          onPressed: () =>
              showFolderDefaultsDialog(context, ref, folderId: folderId),
          child: const Text('Open'),
        );
      }),
    ),
  ));
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('open')));
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('saves username/port/authRef to the folder', (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_folder_def'));
    final store = await tester.runAsync(() => _seededStore(tmp!));

    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWith((ref) async => store!),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            key: const Key('open'),
            onPressed: () =>
                showFolderDefaultsDialog(context, ref, folderId: 'work'),
            child: const Text('Open'),
          );
        }),
      ),
    ));
    await tester.pump();

    // showFolderDefaultsDialog awaits ref.read(secureStoreProvider.future)
    // before showing — drive that real async with runAsync, then settle.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('open')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('folderUsername')), 'deploy');
    await tester.enterText(find.byKey(const Key('folderPort')), '2222');

    // Select existing identity 'i1' from the dropdown.
    await tester.tap(find.byKey(const Key('folderIdentity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shared-key').last);
    await tester.pumpAndSettle();

    // _save() awaits the store mutate — drive it with runAsync too.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('saveFolderDefaults')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    final folders = store!.snapshot().valueOrNull!.folders;
    final work = folders.firstWhere((f) => f.id == 'work');
    expect(work.username, 'deploy');
    expect(work.port, 2222);
    expect(work.authRef, 'i1');

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  // Regression: a folder pointing at a deleted identity must not crash the
  // dialog. DropdownButton asserts value matches one item; the dangling ref is
  // surfaced as an explicit "(eksik kimlik — silinmiş)" item instead.
  testWidgets('dangling authRef does not crash the dialog', (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_dangling'));
    final store = await tester.runAsync(() => _customStore(
          tmp!,
          folders: const [
            Folder(
              id: 'work',
              parentId: null,
              name: 'work',
              username: null,
              port: null,
              authRef: 'ghost', // points at an identity that does not exist
              order: 0,
            ),
          ],
          identities: const [
            Identity(
              id: 'i1',
              label: 'real-key',
              type: IdentityType.privateKey,
              secret: 'PEM',
              passphrase: null,
            ),
          ],
        ));

    final container = await _openDialog(tester, store!, 'work');

    // The dialog rendered (no DropdownButton assertion) and flags the dangling
    // reference instead of throwing.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('saveFolderDefaults')), findsOneWidget);
    expect(find.text('(eksik kimlik — silinmiş)'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  // Regression: a non-numeric port must surface an error and leave the folder's
  // configured port untouched, rather than silently clearing it to "inherit".
  testWidgets('non-numeric port is rejected and keeps the existing port',
      (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_badport'));
    final store = await tester.runAsync(() => _customStore(
          tmp!,
          folders: const [
            Folder(
              id: 'work',
              parentId: null,
              name: 'work',
              username: null,
              port: 2222, // a real configured port we must not lose
              authRef: null,
              order: 0,
            ),
          ],
          identities: const [],
        ));

    final container = await _openDialog(tester, store!, 'work');

    await tester.enterText(find.byKey(const Key('folderPort')), '22x');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('saveFolderDefaults')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // Dialog stays open with an error; the stored port is unchanged.
    expect(find.byKey(const Key('saveFolderDefaults')), findsOneWidget);
    expect(find.textContaining('Port 1–65535'), findsOneWidget);
    final work = store.snapshot().valueOrNull!.folders.firstWhere(
          (f) => f.id == 'work',
        );
    expect(work.port, 2222);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
