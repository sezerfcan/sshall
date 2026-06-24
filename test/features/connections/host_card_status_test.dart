import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/resolve/connection_resolver.dart';
import 'package:sshall/features/connections/host_detail_card.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/status_colors.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/widgets/host_card.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: child),
  );

  Color dotColor(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(HostCard),
            matching: find.byType(Container),
          )
          .last,
    );
    return (container.decoration as BoxDecoration).color!;
  }

  testWidgets('live connected session → green dot', (tester) async {
    await tester.pumpWidget(
      host(
        const HostCard(
          name: 'web1',
          addr: 'root@web1:22',
          connected: true,
          status: SessionStatus.connected(),
        ),
      ),
    );
    await tester.pump();
    expect(
      dotColor(tester),
      statusColor(SessionState.connected, null, AppColors.night),
    );
  });

  testWidgets('no live session → dim dot (idle)', (tester) async {
    await tester.pumpWidget(
      host(
        const HostCard(name: 'web1', addr: 'root@web1:22', connected: false),
      ),
    );
    await tester.pump();
    expect(dotColor(tester), AppColors.night.textDim);
  });

  testWidgets('connecting session → amber dot (never gray)', (tester) async {
    await tester.pumpWidget(
      host(
        const HostCard(
          name: 'web1',
          addr: 'root@web1:22',
          connected: false,
          status: SessionStatus.connecting(),
        ),
      ),
    );
    await tester.pump();
    expect(dotColor(tester), AppColors.night.amber);
    expect(dotColor(tester), isNot(AppColors.night.textDim));
  });

  group('HostDetailCard reflects the live status', () {
    const conn = Connection(
      id: 'c1',
      label: 'web',
      host: 'web1',
      folderId: null,
      username: 'root',
      port: 22,
      authRef: 'i1',
      tags: [],
      order: 0,
    );
    const resolved = ResolvedConnection(
      connection: conn,
      username: 'root',
      port: 22,
      authRef: 'i1',
    );

    testWidgets('idle → "Bağlı değil" pill + cipher "—"', (tester) async {
      await tester.pumpWidget(
        host(
          const HostDetailCard(
            connection: conn,
            resolved: resolved,
            identity: null,
            folders: [],
            onConnect: _noop,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Bağlı değil'), findsOneWidget);
      // Cipher cell shows the placeholder when idle (auth cell may also be '—'
      // for a null identity, so at least one '—' is present).
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('connected → real label "Bağlı" + real cipher', (tester) async {
      await tester.pumpWidget(
        host(
          const HostDetailCard(
            connection: conn,
            resolved: resolved,
            identity: null,
            folders: [],
            status: SessionStatus.connected(),
            cipher: 'aes256-gcm',
            onConnect: _noop,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Bağlı'), findsOneWidget);
      expect(find.text('Bağlı değil'), findsNothing);
      expect(find.text('aes256-gcm'), findsOneWidget);
    });
  });
}

void _noop() {}
