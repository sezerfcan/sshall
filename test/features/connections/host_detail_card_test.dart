import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/resolve/connection_resolver.dart';
import 'package:sshall/features/connections/host_detail_card.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  const conn = Connection(
    id: 'c1',
    label: 'web',
    host: 'h',
    folderId: null,
    username: 'root',
    port: 22,
    authRef: 'i1',
    tags: [],
    order: 0,
  );

  testWidgets('edit button is enabled and fires onEdit when provided',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: HostDetailCard(
          connection: conn,
          resolved: const ResolvedConnection(
              connection: conn, username: 'root', port: 22, authRef: 'i1'),
          identity: null,
          folders: const [],
          onConnect: () {},
          onEdit: () => tapped = true,
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
