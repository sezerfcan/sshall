import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/features/vault/identity_row.dart';
import 'package:sshall/features/vault/identity_view_model.dart';
import 'package:sshall/theme/app_colors.dart';

import '_identity_fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  Identity identity, {
  int usage = 0,
  VoidCallback? onOpen,
  ValueChanged<IdentityRowAction>? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 760,
            child: IdentityRow(
              view: IdentityView.of(identity),
              usage: usage,
              onOpen: onOpen ?? () {},
              onAction: onAction ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    '(a) key row shows the REAL algorithm tag, not generic "Anahtar"',
    (tester) async {
      await _pump(tester, keyIdentity());
      expect(find.text('ED25519'), findsOneWidget);
      expect(find.text('Anahtar'), findsNothing);
    },
  );

  testWidgets('(b) usage badge reflects the count', (tester) async {
    await _pump(tester, keyIdentity(), usage: 2);
    expect(find.text('2 bağlantı'), findsOneWidget);
    expect(find.text('Kullanılmıyor'), findsNothing);
  });

  testWidgets('(b2) usage badge shows "Kullanılmıyor" at zero', (tester) async {
    await _pump(tester, keyIdentity(), usage: 0);
    expect(find.text('Kullanılmıyor'), findsOneWidget);
  });

  testWidgets('(c) key row shows a truncated mono fingerprint', (tester) async {
    await _pump(tester, keyIdentity());
    // The full fingerprint is not shown inline (it is truncated head…tail).
    expect(find.text(edFp), findsNothing);
    // The head segment is present.
    expect(find.textContaining(edFp.substring(0, 12)), findsOneWidget);
  });

  testWidgets('(d) password row shows NO fingerprint cell and no "—"', (
    tester,
  ) async {
    await _pump(tester, passwordIdentity());
    expect(find.text('—'), findsNothing);
    expect(find.text('Parola'), findsOneWidget);
    // No copy-fingerprint affordance for a password.
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });

  testWidgets('(e) tapping the row fires onOpen', (tester) async {
    var opened = false;
    await _pump(tester, keyIdentity(), onOpen: () => opened = true);
    await tester.tap(find.text('prod-key'));
    expect(opened, isTrue);
  });

  testWidgets('(e2) kebab actions fire the matching callback', (tester) async {
    IdentityRowAction? fired;
    await _pump(tester, keyIdentity(), onAction: (a) => fired = a);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeniden adlandır'));
    await tester.pumpAndSettle();
    expect(fired, IdentityRowAction.rename);
  });

  testWidgets('(f) the secret is NEVER rendered (ADR 0005)', (tester) async {
    await _pump(tester, keyIdentity(), usage: 1);
    expect(find.textContaining('PRIVATE-PEM-NEVER-SHOWN'), findsNothing);
  });
}
