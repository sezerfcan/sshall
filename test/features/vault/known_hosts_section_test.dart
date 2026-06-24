import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/features/vault/known_hosts_section.dart';
import 'package:sshall/theme/app_colors.dart';

const _pinA = HostKeyPin(
  hostPort: 'web1.example.com:22',
  keyType: 'ssh-ed25519',
  sha256: 'AAAAbbbbCCCCddddEEEEffffGGGGhhhh1111',
);
const _pinB = HostKeyPin(
  hostPort: 'db.internal:2222',
  keyType: 'ssh-rsa',
  sha256: 'ZZZZyyyyXXXXwwww',
);

Future<void> _pump(
  WidgetTester tester, {
  List<HostKeyPin> pins = const [_pinA, _pinB],
  String query = '',
  ValueChanged<HostKeyPin>? onRevoke,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 760,
            child: KnownHostsSection(
              pins: pins,
              query: query,
              onRevoke: onRevoke ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('each pin row shows host:port, keyType, truncated SHA256', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('web1.example.com:22'), findsOneWidget);
    expect(find.text('ssh-ed25519'), findsOneWidget);
    // Truncated, not the full sha — full lives in the tooltip.
    expect(find.text('SHA256:${_pinA.sha256}'), findsNothing);
    // First 12 chars of "SHA256:AAAAbbbb..." == "SHA256:AAAAb".
    expect(find.textContaining('SHA256:AAAAb'), findsOneWidget);
  });

  testWidgets('host query filters the list', (tester) async {
    await _pump(tester, query: 'db');
    expect(find.text('db.internal:2222'), findsOneWidget);
    expect(find.text('web1.example.com:22'), findsNothing);
  });

  testWidgets('revoke affordance fires onRevoke(pin)', (tester) async {
    HostKeyPin? revoked;
    await _pump(tester, pins: const [_pinA], onRevoke: (p) => revoked = p);
    await tester.tap(find.text('İptal et'));
    expect(revoked, _pinA);
  });

  testWidgets('empty state when there are no pins', (tester) async {
    await _pump(tester, pins: const []);
    expect(find.textContaining('Henüz sabitlenmiş'), findsOneWidget);
  });
}
