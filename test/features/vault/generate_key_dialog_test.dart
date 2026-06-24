import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/vault/generate_key_dialog.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/keygen/key_generator.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

class _FakeKeyGenerator implements KeyGenerator {
  @override
  Future<GeneratedKey> generate({
    required KeyAlgorithm algorithm,
    EcdsaCurve curve = EcdsaCurve.p256,
    int rsaBits = 4096,
    required String comment,
  }) async =>
      GeneratedKey(
        algorithm: algorithm,
        privateKeyPem:
            '-----BEGIN OPENSSH PRIVATE KEY-----\nFAKE\n-----END OPENSSH PRIVATE KEY-----',
        publicKeyOpenSSH: 'ssh-ed25519 AAAAFAKE $comment',
        fingerprint: 'SHA256:FAKEFAKEFAKE',
      );
}

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
  testWidgets('generates, saves identity, and shows copyable public key',
      (tester) async {
    final tmp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_keygen_dlg'));
    final store = await tester.runAsync(() => _unlockedStore(tmp!));

    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWith((ref) async => store!),
      keyGeneratorProvider.overrideWithValue(_FakeKeyGenerator()),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Consumer(builder: (context, ref, _) {
          return Scaffold(
            body: ElevatedButton(
              key: const Key('openGenerateKey'),
              onPressed: () => showGenerateKeyDialog(context, ref),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('openGenerateKey')));
    await tester.pumpAndSettle();

    // Generate with defaults (Ed25519). The fake generator is immediate but the
    // vault mutate does real file IO — drive it with runAsync, then settle.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('generateKeyConfirm')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    // Result screen shows the public key line.
    expect(find.textContaining('ssh-ed25519 AAAAFAKE'), findsOneWidget);

    // ADR 0005: the private key must never be rendered — only the public key
    // and fingerprint are shown.
    expect(find.textContaining('PRIVATE KEY'), findsNothing);
    expect(find.textContaining('FAKE\n'), findsNothing);

    // Identity was persisted to the vault.
    expect(store!.snapshot().valueOrNull!.identities, hasLength(1));
    expect(store.snapshot().valueOrNull!.identities.first.type,
        IdentityType.privateKey);

    // Copy button puts the public key on the clipboard.
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.tap(find.byKey(const Key('copyPublicKey')));
    await tester.pump();
    expect(copied, contains('ssh-ed25519 AAAAFAKE'));

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
