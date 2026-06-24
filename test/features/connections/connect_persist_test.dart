import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/connections/connections_view.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

/// An SshService whose connect always fails (handshake/spawn failure path), to
/// assert that a FAILED "Bağlan ve kaydet" still persists the host (ADR 0031
/// D4 — the old bug lost data when connect failed).
class _FailingSshService extends SshService {
  @override
  Future<SshSession> connect(SshConnectParams params) async {
    throw StateError('connect failed (test)');
  }
}

Future<SecureStore> _emptyStore(
  Directory dir, {
  List<Identity> identities = const [],
}) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  if (identities.isNotEmpty) {
    await store.mutate((v) => v.copyWith(identities: identities));
  }
  return store;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  SecureStore store, {
  SshService? ssh,
}) async {
  final container = ProviderContainer(
    overrides: [
      secureStoreProvider.overrideWith((ref) async => store),
      if (ssh != null) sshServiceProvider.overrideWithValue(ssh),
    ],
  );
  await tester.runAsync(() => container.read(secureStoreProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: const Scaffold(body: ConnectionsView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Opens the connect dialog through the real ConnectionsView listener by
/// bumping newHostRequestProvider (the same trigger the sidebar "+" uses).
Future<void> _openDialog(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.runAsync(() async {
    container.read(newHostRequestProvider.notifier).state++;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pumpAndSettle();
}

Future<void> _fillBasic(
  WidgetTester tester, {
  String label = 'Box',
  String pw = 'pw',
}) async {
  await tester.enterText(find.byKey(const Key('label')), label);
  await tester.enterText(find.byKey(const Key('host')), 'example.com');
  await tester.enterText(find.byKey(const Key('username')), 'root');
  await tester.enterText(find.byKey(const Key('password')), pw);
  await tester.pump();
}

void main() {
  testWidgets('a: "Kaydet" persists a Connection and opens NO session', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_persist_a'),
    );
    final store = await tester.runAsync(() => _emptyStore(tmp!));
    final container = await _pump(tester, store!);

    await _openDialog(tester, container);
    await _fillBasic(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('saveOnly')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    final conns = store.snapshot().valueOrNull!.connections;
    expect(conns.length, 1);
    expect(conns.first.host, 'example.com');
    // No terminal/session tab was opened.
    expect(container.read(tabsControllerProvider).tabs, isEmpty);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('b: a FAILED "Bağlan ve kaydet" still persists the host (D4)', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_persist_b'),
    );
    final store = await tester.runAsync(() => _emptyStore(tmp!));
    final container = await _pump(tester, store!, ssh: _FailingSshService());

    await _openDialog(tester, container);
    await _fillBasic(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('saveAndConnect')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();

    // Connect threw, but the host is saved anyway (the regression we fixed).
    final conns = store.snapshot().valueOrNull!.connections;
    expect(conns.length, 1);
    expect(conns.first.host, 'example.com');
    expect(container.read(tabsControllerProvider).tabs, isEmpty);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('c: reusing an existing identity does NOT mint a new one (D8)', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_persist_c'),
    );
    final store = await tester.runAsync(
      () => _emptyStore(
        tmp!,
        identities: const [
          Identity(
            id: 'i1',
            label: 'shared-key',
            type: IdentityType.privateKey,
            secret: 'PEM',
            passphrase: null,
          ),
        ],
      ),
    );
    final container = await _pump(tester, store!);

    await _openDialog(tester, container);
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.enterText(find.byKey(const Key('host')), 'example.com');
    await tester.enterText(find.byKey(const Key('username')), 'root');

    // Key mode → pick the existing identity.
    await tester.tap(find.byKey(const Key('authSegKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('authIdentity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shared-key').last);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('saveOnly')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    final data = store.snapshot().valueOrNull!;
    // Still exactly one identity — no duplicate minted.
    expect(data.identities.length, 1);
    expect(data.connections.single.authRef, 'i1');

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('d: a fresh typed password mints exactly one new Identity (D8)', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_persist_d'),
    );
    final store = await tester.runAsync(() => _emptyStore(tmp!));
    final container = await _pump(tester, store!);

    await _openDialog(tester, container);
    await _fillBasic(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('saveOnly')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    final data = store.snapshot().valueOrNull!;
    expect(data.identities.length, 1);
    expect(data.identities.single.type, IdentityType.password);
    expect(data.identities.single.secret, 'pw');
    expect(data.connections.single.authRef, data.identities.single.id);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
