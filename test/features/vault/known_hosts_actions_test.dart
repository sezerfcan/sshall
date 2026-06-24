import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/vault/known_hosts_actions.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_colors.dart';

const _pin = HostKeyPin(
  hostPort: 'web1:22',
  keyType: 'ssh-ed25519',
  sha256: 'OLDoldOLDoldOLDold1234',
);

Future<SecureStore> _store(Directory dir, List<HostKeyPin> pins) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate((v) => v.copyWith(pins: pins));
  return store;
}

Widget _host(Widget Function(BuildContext) builder) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.night]),
  home: Scaffold(body: Builder(builder: builder)),
);

void main() {
  testWidgets('revoke confirmation warns about TOFU and shows OLD fingerprint', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_pin'),
    );
    final store = await tester.runAsync(() => _store(tmp!, const [_pin]));

    await tester.pumpWidget(
      _host(
        (context) => ElevatedButton(
          onPressed: () => revokePinFlow(context, store!, _pin),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Security framing: warns the next connect re-triggers trust-on-first-use.
    expect(find.textContaining('yeniden sorulur'), findsOneWidget);
    // The OLD fingerprint is shown for comparison.
    expect(find.text('SHA256:${_pin.sha256}'), findsOneWidget);
    // No one-click re-pin / re-trust shortcut — only Vazgeç + Unut.
    expect(find.text('Unut'), findsOneWidget);
    expect(find.text('Vazgeç'), findsOneWidget);
    expect(find.textContaining('Yeniden'), findsNothing);
    expect(find.textContaining('Yeniden güven'), findsNothing);

    // Confirm → pin forgotten (single mutate).
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirmRevokePin')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(store!.snapshot().valueOrNull!.pins, isEmpty);
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('cancel keeps the pin', (tester) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_pin2'),
    );
    final store = await tester.runAsync(() => _store(tmp!, const [_pin]));

    await tester.pumpWidget(
      _host(
        (context) => ElevatedButton(
          onPressed: () => revokePinFlow(context, store!, _pin),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(store!.snapshot().valueOrNull!.pins, hasLength(1));
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
