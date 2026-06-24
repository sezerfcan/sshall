import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/resolve/connection_resolver.dart';
import 'package:sshall/features/connections/host_detail_card.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  testWidgets('SFTP button invokes onOpenSftp', (tester) async {
    var opened = false;
    const conn = Connection(
      id: 'c1',
      label: 'web',
      host: 'example.com',
      folderId: null,
      username: 'root',
      port: 22,
      authRef: 'id1',
      tags: [],
      order: 0,
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: HostDetailCard(
          connection: conn,
          // ResolvedConnection.connection is non-null in production; pass the
          // real connection (the brief's null placeholder won't type-check).
          resolved: const ResolvedConnection(
              connection: conn, username: 'root', port: 22, authRef: 'id1'),
          identity: null,
          folders: const [],
          onConnect: () {},
          onOpenSftp: () => opened = true,
        ),
      ),
    ));
    await tester.tap(find.text('SFTP'));
    await tester.pump();
    expect(opened, true);
  });
}
