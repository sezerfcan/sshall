import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/connections/connections_view.dart';
import 'package:sshall/features/connections/recent_targets_controller.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart';

/// Integration coverage for the Quick Connect routing (ADR 0034 D2/D5): a
/// saved-host match connects EPHEMERALLY (reaches _connect) and writes NO new
/// vault entry; a brand-new host falls back to the prefilled dialog; the
/// successful ephemeral target is recorded in recents (and ONLY the
/// `user@host:port` string — no secret).

/// Records every connect; returns a benign in-memory test session so the
/// terminal tab path runs without a real isolate/SSH.
class _FakeSshService implements SshService {
  final List<SshConnectParams> calls = [];
  @override
  Future<SshSession> connect(SshConnectParams params) async {
    calls.add(params);
    return SshSession.test();
  }
}

Future<SecureStore> _seededStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate(
    (v) => VaultData(
      connections: [
        const Connection(
          id: 'c-web',
          label: 'Prod Web',
          host: 'web.example.com',
          folderId: null,
          username: 'root',
          port: 22,
          authRef: 'id-1',
          tags: [],
          order: 0,
        ),
      ],
      folders: v.folders,
      identities: [
        const Identity(
          id: 'id-1',
          label: 'web-pw',
          type: IdentityType.password,
          secret: 'hunter2',
          passphrase: null,
        ),
      ],
      pins: v.pins,
    ),
  );
  return store;
}

void main() {
  Future<(ProviderContainer, _FakeSshService, Directory)> boot(
    WidgetTester tester,
  ) async {
    final tmp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_qc_route'),
    ))!;
    final store = await tester.runAsync(() => _seededStore(tmp));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ssh = _FakeSshService();

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
        sshServiceProvider.overrideWithValue(ssh),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (container, ssh, tmp);
  }

  int connCount(ProviderContainer c) =>
      c
          .read(secureStoreProvider)
          .valueOrNull
          ?.snapshot()
          .valueOrNull
          ?.connections
          .length ??
      -1;

  Finder field() => find.byKey(const Key('quickConnectInput'));

  testWidgets(
    'saved-host match connects EPHEMERALLY and writes NO new Connection',
    (tester) async {
      final (container, ssh, tmp) = await boot(tester);
      final before = connCount(container);

      // Type a target that matches the saved host (by host) and submit.
      await tester.enterText(field(), 'root@web.example.com:22');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // _connect was reached with the SAVED identity's resolved params.
      expect(ssh.calls, isNotEmpty);
      expect(ssh.calls.single.host, 'web.example.com');
      expect(ssh.calls.single.password, 'hunter2'); // reused stored identity

      // CRITICAL: no new vault entry (no silent persist — ADR 0034 D2).
      expect(connCount(container), before);

      // A terminal tab opened (component-3 feedback path inherited).
      final tabs = container.read(tabsControllerProvider);
      expect(tabs.tabs.values.any((t) => t.kind == TabKind.terminal), isTrue);

      // Recents recorded the target string ONLY (no secret).
      final recents = container.read(recentTargetsControllerProvider);
      expect(recents, contains('root@web.example.com:22'));
      expect(recents.any((r) => r.contains('hunter2')), isFalse);

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );

  testWidgets(
    'brand-new host falls back to the prefilled dialog (no persist)',
    (tester) async {
      final (container, ssh, tmp) = await boot(tester);
      final before = connCount(container);

      await tester.enterText(field(), 'admin@brand-new.example.org:2200');
      // _openConnect awaits the secure-store future before showing the dialog;
      // run that microtask under runAsync, then pump the dialog frames. The bar
      // shows an in-flight spinner while the dialog is open, so pumpAndSettle
      // never quiesces — use explicit frames.
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The full "Yeni Bağlantı" dialog opened, prefilled from the parse.
      expect(find.text('Yeni Bağlantı'), findsOneWidget);
      final host = tester.widget<TextField>(find.byKey(const Key('host')));
      expect(host.controller!.text, 'brand-new.example.org');
      final port = tester.widget<TextField>(find.byKey(const Key('port')));
      expect(port.controller!.text, '2200');

      // The bar itself did NOT connect or persist (saving is the dialog's job).
      expect(ssh.calls, isEmpty);
      expect(connCount(container), before);

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );
}
