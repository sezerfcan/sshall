import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/settings/settings_view.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  testWidgets('danger-zone reset wipes the vault and re-locks the session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await tester.runAsync(() => SharedPreferences.getInstance());

    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_settings_reset'),
    );
    final store = SecureStore(
      crypto: CryptoService(),
      file: VaultFile('${dir!.path}/vault.bin'),
      keyring: InMemoryKeyring(),
    );
    await tester.runAsync(() => store.create('pw'));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs!),
        secureStoreProvider.overrideWith((ref) async => store),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));
    container.read(sessionUnlockedProvider.notifier).state = true;
    // Seed a decrypted selection so we can prove the reset tears down the
    // session-scoped state (not just the unlock flag). A live activeSession
    // needs a real SSH worker, so we assert on selectedConnection instead; the
    // teardown clears both via the same code path.
    container
        .read(selectedConnectionProvider.notifier)
        .state = const Connection(
      id: 'c1',
      label: 'seed',
      host: 'example.com',
      folderId: null,
      username: 'root',
      port: 22,
      authRef: null,
      tags: [],
      order: 0,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The danger zone is a separated nav entry now (ADR 0038 D1/D10): open it,
    // then trigger the (preserved) reset-vault action.
    await tester.tap(find.byKey(const Key('settingsNav_Tehlikeli Bölge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsResetVault')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('resetConfirmPhrase')),
      'SIFIRLA',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirmReset')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // Settle: drive framework frames AND real file IO so the dialog's
    // Navigator.pop advances, showResetVaultDialog's future resolves, and
    // store.reset() actually runs before the assertions are checked. This only
    // gives the already-correct behavior time to complete; it cannot mask a
    // non-reset because it sits BEFORE the (unchanged) assertions.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }

    expect(await tester.runAsync(() => store.vaultExists()), isFalse);
    expect(container.read(sessionUnlockedProvider), isFalse); // re-locked
    // The session-scoped teardown ran: the decrypted connection is gone.
    expect(container.read(selectedConnectionProvider), isNull);

    container.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
