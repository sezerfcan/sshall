import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
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
  }) async => GeneratedKey(
    algorithm: algorithm,
    privateKeyPem:
        '-----BEGIN OPENSSH PRIVATE KEY-----\nFAKE\n-----END OPENSSH PRIVATE KEY-----',
    publicKeyOpenSSH: 'ssh-ed25519 AAAAPERSIST $comment',
    fingerprint: 'SHA256:PERSISTED',
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
  testWidgets('generation persists publicKey/fingerprint/createdAt (D1)', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_persist'),
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
          home: Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => showGenerateKeyDialog(context, ref),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('generateKeyConfirm')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    final stored = store!.snapshot().valueOrNull!.identities.single;
    // Default label/comment when the fields are left empty.
    expect(
      stored.publicKeyOpenSSH,
      'ssh-ed25519 AAAAPERSIST üretilen anahtar@sshall',
      reason: 'public key persisted, not discarded',
    );
    expect(stored.fingerprint, 'SHA256:PERSISTED');
    expect(stored.createdAt, isNotNull);
    expect(stored.createdAt! > 0, isTrue);

    container.dispose();
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
