import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/unlock/unlock_screen.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

Future<(SecureStore, Directory)> _existingVault(WidgetTester tester) async {
  final dir = await tester
      .runAsync(() => Directory.systemTemp.createTemp('sshall_unlock_reset'));
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir!.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await tester.runAsync(() => store.create('pw'));
  store.lock(); // present the "unlock" screen, not "create"
  return (store, dir);
}

Future<ProviderContainer> _pump(WidgetTester tester, SecureStore store) async {
  final container = ProviderContainer(overrides: [
    secureStoreProvider.overrideWith((ref) async => store),
  ]);
  await tester.runAsync(() => container.read(secureStoreProvider.future));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: UnlockScreen(onUnlocked: () {}),
    ),
  ));
  // Let vaultExists() resolve in the FutureBuilder.
  await tester.runAsync(() async =>
      Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('forgot-passphrase reset wipes the vault and returns to create',
      (tester) async {
    final (store, dir) = await _existingVault(tester);
    final container = await _pump(tester, store);

    expect(find.text("Vault'u Aç"), findsOneWidget);
    expect(find.byKey(const Key('forgotPassphrase')), findsOneWidget);

    await tester.tap(find.byKey(const Key('forgotPassphrase')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('resetConfirmPhrase')), 'SIFIRLA');
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirmReset')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    // Drive the dialog pop + _reset() through to its real filesystem IO: the
    // tap above only enqueued the pointer event. Each pump advances the
    // framework (route-pop, the _reset() continuation, store.reset()'s queue);
    // each runAsync lets the real file-delete IO complete. Additive settling
    // only — no assertion is relaxed.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
    }

    // Vault wiped (essential, behaviour-level guarantee).
    expect(await tester.runAsync(() => store.vaultExists()), isFalse);

    // The screen rebuilt: _reset()'s setState recreated the FutureBuilder, whose
    // vaultExists() is real IO. First settle renders the spinner; a second
    // runAsync lets that IO resolve; the final settle renders "create" mode.
    await tester.pumpAndSettle();
    await tester.runAsync(() async =>
        Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Vault Oluştur'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('forgot-passphrase link is hidden when no vault exists',
      (tester) async {
    final dir = await tester
        .runAsync(() => Directory.systemTemp.createTemp('sshall_unlock_novault'));
    final store = SecureStore(
      crypto: CryptoService(),
      file: VaultFile('${dir!.path}/vault.bin'),
      keyring: InMemoryKeyring(),
    );
    final container = await _pump(tester, store);

    expect(find.text('Vault Oluştur'), findsOneWidget);     // create mode
    expect(find.byKey(const Key('forgotPassphrase')), findsNothing);

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
