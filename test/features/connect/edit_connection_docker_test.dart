import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/resolve/connection_resolver.dart';
import 'package:sshall/features/connect/edit_connection_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

Connection _conn({bool docker = false, String? dockerBinary}) => Connection(
  id: 'c1',
  label: 'web',
  host: '10.0.0.1',
  folderId: null,
  username: 'root',
  port: 2222,
  authRef: 'i1',
  tags: const ['prod'],
  order: 0,
  docker: docker,
  dockerBinary: dockerBinary,
);

Identity _identity() => const Identity(
  id: 'i1',
  label: 'web',
  type: IdentityType.password,
  secret: 'pw',
  passphrase: null,
);

void main() {
  testWidgets('shows Docker switch off; binary field appears when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Switch present and off; binary field absent initially.
    final switchFinder = find.byKey(const Key('edit-docker'));
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
    expect(find.byKey(const Key('edit-docker-bin')), findsNothing);

    // Toggle on -> binary field appears.
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    expect(find.byKey(const Key('edit-docker-bin')), findsOneWidget);
  });

  testWidgets('prefills docker on + binary, round-trips through save', (
    tester,
  ) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn(docker: true, dockerBinary: 'sudo docker');
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('edit-docker'));
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    expect(find.byKey(const Key('edit-docker-bin')), findsOneWidget);
    expect(find.text('sudo docker'), findsOneWidget);

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.docker, isTrue);
    expect(result!.dockerBinary, 'sudo docker');
  });

  testWidgets('docker off yields null dockerBinary on save', (tester) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result!.docker, isFalse);
    expect(result!.dockerBinary, isNull);
  });
}
