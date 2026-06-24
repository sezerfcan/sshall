import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/features/vault/identity_detail.dart';
import 'package:sshall/features/vault/identity_view_model.dart';
import 'package:sshall/theme/app_colors.dart';

import '_identity_fixtures.dart';

Connection _conn(String id, String label) => Connection(
  id: id,
  label: label,
  host: 'h',
  folderId: null,
  username: null,
  port: null,
  authRef: 'k1',
  tags: const [],
  order: 0,
);

Future<void> _pump(
  WidgetTester tester, {
  required IdentityView view,
  int usage = 0,
  List<Connection> refs = const [],
  VoidCallback? onRename,
  VoidCallback? onDelete,
  VoidCallback? onExport,
  ValueChanged<Connection>? onJump,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: IdentityDetail(
              view: view,
              usage: usage,
              referencingConnections: refs,
              onRename: onRename ?? () {},
              onDelete: onDelete ?? () {},
              onExport: onExport,
              onJumpToConnection: onJump,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders metadata + full fingerprint + public-key box', (
    tester,
  ) async {
    await _pump(tester, view: IdentityView.of(keyIdentity()), usage: 2);
    expect(find.text('SSH anahtarı'), findsOneWidget);
    expect(find.text('ED25519'), findsWidgets);
    // Full (untruncated) fingerprint is selectable in the box.
    expect(find.text(edFp), findsOneWidget);
    // One-line public key is shown.
    expect(find.text(edPub), findsOneWidget);
  });

  testWidgets('NEVER renders the private key or passphrase (ADR 0005)', (
    tester,
  ) async {
    await _pump(
      tester,
      view: IdentityView.of(keyIdentity(secret: 'PRIVATE-PEM-XYZ')),
    );
    expect(find.textContaining('PRIVATE-PEM-XYZ'), findsNothing);
    expect(find.textContaining('PRIVATE KEY'), findsNothing);
  });

  testWidgets('password identity shows no public-key box', (tester) async {
    await _pump(tester, view: IdentityView.of(passwordIdentity()));
    expect(find.byKey(const Key('detailPublicKey')), findsNothing);
    expect(find.byKey(const Key('detailFingerprint')), findsNothing);
    expect(find.text('Parola'), findsWidgets);
  });

  testWidgets('"Kullanan bağlantılar" jumps on tap', (tester) async {
    Connection? jumped;
    await _pump(
      tester,
      view: IdentityView.of(keyIdentity()),
      usage: 1,
      refs: [_conn('c1', 'web1')],
      onJump: (conn) => jumped = conn,
    );
    await tester.ensureVisible(find.text('web1'));
    await tester.pump();
    await tester.tap(find.text('web1'));
    expect(jumped?.id, 'c1');
  });

  testWidgets('rename affordance fires onRename', (tester) async {
    var renamed = false;
    await _pump(
      tester,
      view: IdentityView.of(keyIdentity()),
      onRename: () => renamed = true,
    );
    await tester.tap(find.byKey(const Key('detailRename')));
    expect(renamed, isTrue);
  });

  testWidgets('export affordance present only when onExport provided', (
    tester,
  ) async {
    await _pump(tester, view: IdentityView.of(keyIdentity()), onExport: () {});
    expect(find.byKey(const Key('detailExport')), findsOneWidget);
  });
}
