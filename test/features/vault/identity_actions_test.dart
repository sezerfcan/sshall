import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/vault/identity_actions.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

import '_identity_fixtures.dart';

Future<SecureStore> _store(Directory dir, VaultData seed) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate((_) => seed);
  return store;
}

Connection _conn(String id, {String? authRef}) => Connection(
  id: id,
  label: id,
  host: 'h',
  folderId: null,
  username: null,
  port: null,
  authRef: authRef,
  tags: const [],
  order: 0,
);

Widget _host(Widget Function(BuildContext) onTapBuilder) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.night]),
  home: Scaffold(body: Builder(builder: onTapBuilder)),
);

void main() {
  testWidgets('deleteIdentityFlow confirmation NAMES the reference count', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_del'),
    );
    final id = keyIdentity(id: 'k1', label: 'prod');
    final seed = VaultData(
      connections: [
        _conn('c1', authRef: 'k1'),
        _conn('c2', authRef: 'k1'),
      ],
      folders: const [],
      identities: [id],
      pins: const [],
    );
    final store = await tester.runAsync(() => _store(tmp!, seed));

    await tester.pumpWidget(
      _host(
        (context) => ElevatedButton(
          onPressed: () => deleteIdentityFlow(context, store!, id, usage: 2),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Confirmation body names the count.
    expect(find.textContaining('2 bağlantı'), findsOneWidget);
    expect(find.textContaining('kimliksiz kalır'), findsOneWidget);

    // Confirm → identity removed + authRefs nulled (single mutate, no dangling).
    // The mutate runs inside the confirm click; drive that click in runAsync so
    // the real file IO completes.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirmDeleteIdentity')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    final v = store!.snapshot().valueOrNull!;
    expect(v.identities, isEmpty);
    expect(v.connections.any((c) => c.authRef == 'k1'), isFalse);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('deleteIdentityFlow cancel leaves everything intact', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_del2'),
    );
    final id = keyIdentity(id: 'k1');
    final seed = VaultData(
      connections: [_conn('c1', authRef: 'k1')],
      folders: const [],
      identities: [id],
      pins: const [],
    );
    final store = await tester.runAsync(() => _store(tmp!, seed));

    await tester.pumpWidget(
      _host(
        (context) => ElevatedButton(
          onPressed: () => deleteIdentityFlow(context, store!, id, usage: 1),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(store!.snapshot().valueOrNull!.identities, hasLength(1));
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('renameIdentityFlow mutates only the label', (tester) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_ren'),
    );
    final id = keyIdentity(id: 'k1', label: 'old');
    final seed = VaultData(
      connections: const [],
      folders: const [],
      identities: [id],
      pins: const [],
    );
    final store = await tester.runAsync(() => _store(tmp!, seed));

    await tester.pumpWidget(
      _host(
        (context) => ElevatedButton(
          onPressed: () => renameIdentityFlow(context, store!, id),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('renameIdentityField')),
      'new-name',
    );
    // The mutate runs inside the Kaydet click; drive it in runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('renameIdentityConfirm')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    final stored = store!.snapshot().valueOrNull!.identities.single;
    expect(stored.label, 'new-name');
    expect(stored.fingerprint, id.fingerprint); // unchanged
    expect(stored.secret, id.secret);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
