import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/connection_actions.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

Future<SecureStore> _makeUnlockedStore({
  required Directory dir,
  required VaultData seed,
}) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('pw');
  await store.mutate((_) => seed);
  return store;
}

void main() {
  testWidgets('editConnectionFlow renames a saved connection', (tester) async {
    final dir = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_conn_actions'));

    const conn = Connection(
      id: 'c1',
      label: 'web',
      host: 'h',
      folderId: null,
      username: 'root',
      port: 22,
      authRef: 'i1',
      tags: [],
      order: 0,
    );

    const seed = VaultData(
      connections: [conn],
      folders: [],
      identities: [
        Identity(
          id: 'i1',
          label: 'web',
          type: IdentityType.password,
          secret: 'pw',
          passphrase: null,
        ),
      ],
      pins: [],
    );

    final store = await tester
        .runAsync(() => _makeUnlockedStore(dir: dir!, seed: seed));

    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWith((ref) async => store!),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => editConnectionFlow(context, ref, conn),
              child: const Text('edit'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // editConnectionFlow awaits ref.read(secureStoreProvider.future) before
    // showing the dialog — tap and then poll until the dialog field appears
    // instead of sleeping a fixed 800 ms.
    await tester.runAsync(() => tester.tap(find.text('edit')));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (find.byKey(const Key('edit-label')).evaluate().isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('edit-label')), 'renamed');

    // _save() pops the dialog synchronously (no await), but updateConnection
    // mutates the store async — poll until the store reflects the rename.
    await tester.runAsync(() => tester.tap(find.text('Kaydet')));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (store!.snapshot().valueOrNull?.connections.single.label ==
            'renamed') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(
      store!.snapshot().valueOrNull!.connections.single.label,
      'renamed',
    );

    container.dispose();
    await tester.runAsync(() => dir!.delete(recursive: true));
  });
}
