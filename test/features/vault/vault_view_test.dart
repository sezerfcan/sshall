import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/vault/vault_view.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/keygen/key_generator.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

import '_identity_fixtures.dart';

/// Build an unlocked SecureStore backed by a real temp VaultFile + InMemoryKeyring,
/// exactly as secure_store_test.dart does.
Future<SecureStore> _unlockedStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  return store;
}

const _testSecret = 'super-secret-password-42';
const _testLabel = 'my-prod-server';

class _FakeKeyGenerator implements KeyGenerator {
  @override
  Future<GeneratedKey> generate({
    required KeyAlgorithm algorithm,
    EcdsaCurve curve = EcdsaCurve.p256,
    int rsaBits = 4096,
    required String comment,
  }) async => const GeneratedKey(
    algorithm: KeyAlgorithm.ed25519,
    privateKeyPem: 'PEM',
    publicKeyOpenSSH: 'ssh-ed25519 AAAAFAKE c',
    fingerprint: 'SHA256:FAKE',
  );
}

void main() {
  testWidgets(
    'VaultView shows pin count and identity label; never shows the secret',
    (tester) async {
      final tmp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('sshall_vault_view'),
      );
      final store = await tester.runAsync(() => _unlockedStore(tmp!));

      // Seed: 1 password identity + 1 host-key pin.
      await tester.runAsync(
        () => store!.mutate(
          (v) => VaultData(
            connections: v.connections,
            folders: v.folders,
            identities: [
              ...v.identities,
              const Identity(
                id: 'id-test-1',
                label: _testLabel,
                type: IdentityType.password,
                secret: _testSecret,
                passphrase: null,
              ),
            ],
            pins: [
              ...v.pins,
              const HostKeyPin(
                hostPort: 'example.com:22',
                keyType: 'ssh-ed25519',
                sha256: 'AAAA1111==',
              ),
            ],
          ),
        ),
      );

      final container = ProviderContainer(
        overrides: [secureStoreProvider.overrideWith((ref) async => store!)],
      );
      await tester.runAsync(() => container.read(secureStoreProvider.future));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppColors.night]),
            home: const Scaffold(body: VaultView()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The identity label must appear.
      expect(find.text(_testLabel), findsWidgets);

      // Pin count stat must show "1".
      expect(find.text('1'), findsWidgets);

      // The vault status must show "Açık".
      expect(find.text('Açık'), findsOneWidget);

      // The secret must NEVER be rendered.
      expect(find.text(_testSecret), findsNothing);

      container.dispose();
      await tester.runAsync(() => tmp!.delete(recursive: true));
    },
  );

  testWidgets('stat row does not overflow at a narrow desktop width', (
    tester,
  ) async {
    // Regression: a narrowed shell (always-visible sidebar) can leave VaultView
    // ~700px wide. The three stat cards must wrap instead of throwing
    // RenderFlex overflow.
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_vault_narrow'),
    );
    final store = await tester.runAsync(() => _unlockedStore(tmp!));

    final container = ProviderContainer(
      overrides: [secureStoreProvider.overrideWith((ref) async => store!)],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: VaultView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // No RenderFlex overflow (or any other) should have been thrown.
    expect(tester.takeException(), isNull);
    // All three stat cards still render their content.
    expect(find.text('SSH Anahtarı'), findsOneWidget);
    expect(find.text('Bilinen Host'), findsOneWidget);
    expect(find.text('Açık'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('generate-key button opens the generate dialog', (tester) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_vault_gen'),
    );
    final store = await tester.runAsync(() => _unlockedStore(tmp!));

    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWith((ref) async => store!),
        keyGeneratorProvider.overrideWithValue(_FakeKeyGenerator()),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: VaultView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('generateKey')));
    await tester.pumpAndSettle();
    expect(find.text('Yeni SSH anahtarı üret'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  // ── Görev 8: interactive vault assembly ──────────────────────────────────

  Future<(ProviderContainer, SecureStore, Directory)> interactiveVault(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_vault_i'),
    ))!;
    final store = (await tester.runAsync(() => _unlockedStore(tmp)))!;

    await tester.runAsync(
      () => store.mutate(
        (v) => v.copyWith(
          identities: [keyIdentity(id: 'k1', label: 'prod-key')],
          pins: const [
            HostKeyPin(
              hostPort: 'web1.example.com:22',
              keyType: 'ssh-ed25519',
              sha256: 'PINpinPINpin1234',
            ),
          ],
        ),
      ),
    );

    final container = ProviderContainer(
      overrides: [secureStoreProvider.overrideWith((ref) async => store)],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: VaultView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (container, store, tmp);
  }

  testWidgets(
    'list shows real algorithm tag; no dead "—", no generic "Anahtar"',
    (tester) async {
      final (container, _, tmp) = await interactiveVault(tester);
      expect(find.text('ED25519'), findsOneWidget);
      expect(find.text('—'), findsNothing); // dead fingerprint removed
      expect(find.text('Anahtar'), findsNothing); // generic tag removed
      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );

  testWidgets('search filters the identity list', (tester) async {
    final (container, _, tmp) = await interactiveVault(tester);
    await tester.enterText(find.byKey(const Key('vaultSearch')), 'rsa');
    await tester.pump();
    expect(find.text('prod-key'), findsNothing); // ed25519 filtered out
    await tester.enterText(find.byKey(const Key('vaultSearch')), 'ed25519');
    await tester.pump();
    expect(find.text('prod-key'), findsOneWidget);
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('tapping a row opens the detail view', (tester) async {
    final (container, _, tmp) = await interactiveVault(tester);
    await tester.tap(find.byKey(const Key('identityRow-k1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detailPublicKey')), findsOneWidget);
    expect(find.text(edPub), findsOneWidget);
    // The private key is never rendered.
    expect(find.textContaining('PRIVATE-PEM-NEVER-SHOWN'), findsNothing);
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('known-hosts section lists pins and host search filters', (
    tester,
  ) async {
    final (container, _, tmp) = await interactiveVault(tester);
    // SectionLabel renders upper-cased ("BILINEN HOSTLAR").
    expect(find.text('Bilinen Hostlar'.toUpperCase()), findsOneWidget);
    expect(find.text('web1.example.com:22'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hostSearch')), 'nope');
    await tester.pump();
    expect(find.text('web1.example.com:22'), findsNothing);
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('delete action via kebab removes the identity (single mutate)', (
    tester,
  ) async {
    final (container, store, tmp) = await interactiveVault(tester);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmDeleteIdentity')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirmDeleteIdentity')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(store.snapshot().valueOrNull!.identities, isEmpty);
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets(
    'tapping a "Kullanan bağlantılar" row jumps to that connection and '
    'closes the vault overlay',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tmp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sshall_vault_jump'),
      ))!;
      final store = (await tester.runAsync(() => _unlockedStore(tmp)))!;

      // Seed an identity (k1) and a connection that references it (authRef:k1)
      // so the detail's "Kullanan bağlantılar" list has a clickable row.
      const conn = Connection(
        id: 'c1',
        label: 'web1',
        host: 'web1.example.com',
        folderId: null,
        username: null,
        port: null,
        authRef: 'k1',
        tags: [],
        order: 0,
      );
      await tester.runAsync(
        () => store.mutate(
          (v) => v.copyWith(
            identities: [keyIdentity(id: 'k1', label: 'prod-key')],
            connections: const [conn],
          ),
        ),
      );

      final container = ProviderContainer(
        overrides: [secureStoreProvider.overrideWith((ref) async => store)],
      );
      await tester.runAsync(() => container.read(secureStoreProvider.future));

      // Start with the vault overlay open and a different (or no) selection so
      // the jump's state changes are observable.
      container.read(activeOverlayProvider.notifier).state = ShellOverlay.vault;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppColors.night]),
            home: const Scaffold(body: VaultView()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open the detail for k1, then tap its used-by connection row.
      await tester.tap(find.byKey(const Key('identityRow-k1')));
      await tester.pumpAndSettle();
      expect(find.text('web1'), findsOneWidget);
      await tester.tap(find.text('web1'));
      await tester.pumpAndSettle();

      // The jump selected that connection, requested the connection home, and
      // closed the vault overlay (so the user lands on the connection's detail).
      expect(container.read(selectedConnectionProvider)?.id, 'c1');
      expect(container.read(homeRequestedProvider), isTrue);
      expect(container.read(activeOverlayProvider), ShellOverlay.none);
      // The detail dialog was popped.
      expect(find.byKey(const Key('detailPublicKey')), findsNothing);

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );
}
