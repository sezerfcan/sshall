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

/// A fresh (non-existent) vault so the screen renders in "create" mode.
Future<(SecureStore, Directory)> _freshVault(WidgetTester tester) async {
  final dir = await tester
      .runAsync(() => Directory.systemTemp.createTemp('sshall_create_confirm'));
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir!.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  return (store, dir);
}

Future<ProviderContainer> _pump(
    WidgetTester tester, SecureStore store, void Function() onUnlocked) async {
  final container = ProviderContainer(overrides: [
    secureStoreProvider.overrideWith((ref) async => store),
  ]);
  await tester.runAsync(() => container.read(secureStoreProvider.future));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: UnlockScreen(onUnlocked: onUnlocked),
    ),
  ));
  await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('create mode shows a confirm-passphrase field', (tester) async {
    final (store, dir) = await _freshVault(tester);
    final container = await _pump(tester, store, () {});

    expect(find.text('Vault Oluştur'), findsOneWidget);
    expect(find.byKey(const Key('passphrase')), findsOneWidget);
    // The new confirm field only exists while creating a vault.
    expect(find.byKey(const Key('passphraseConfirm')), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('mismatched passphrases block creation and show an error',
      (tester) async {
    final (store, dir) = await _freshVault(tester);
    var unlocked = false;
    final container = await _pump(tester, store, () => unlocked = true);

    await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse');
    await tester.enterText(
        find.byKey(const Key('passphraseConfirm')), 'wrong horse');
    await tester.pump();

    await tester.tap(find.text('Oluştur'));
    await tester.pump();

    // Vault must NOT be created and onUnlocked must NOT fire.
    expect(unlocked, isFalse);
    expect(await tester.runAsync(() => store.vaultExists()), isFalse);
    expect(find.text('Parolalar eşleşmiyor'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('matching passphrases create the vault and unlock', (tester) async {
    final (store, dir) = await _freshVault(tester);
    var unlocked = false;
    final container = await _pump(tester, store, () => unlocked = true);

    await tester.enterText(find.byKey(const Key('passphrase')), 'matching pass');
    await tester.enterText(
        find.byKey(const Key('passphraseConfirm')), 'matching pass');
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Oluştur'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    }

    expect(unlocked, isTrue);
    expect(await tester.runAsync(() => store.vaultExists()), isTrue);

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('passphrase visibility can be toggled in create mode',
      (tester) async {
    final (store, dir) = await _freshVault(tester);
    final container = await _pump(tester, store, () {});

    // Toggle exists and flips the obscure state of the master field.
    final toggle = find.byKey(const Key('passphraseVisibility'));
    expect(toggle, findsOneWidget);

    // fieldKey is applied to the TextField itself, so the keyed widget is the
    // TextField (not a wrapper).
    TextField masterField() =>
        tester.widget<TextField>(find.byKey(const Key('passphrase')));

    expect(masterField().obscureText, isTrue); // hidden by default
    await tester.tap(toggle);
    await tester.pump();
    expect(masterField().obscureText, isFalse); // now revealed

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
