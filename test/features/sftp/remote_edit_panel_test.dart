import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/remote_edit_panel.dart';
import 'package:sshall/features/sftp/remote_edit_session.dart';
import 'package:sshall/theme/app_colors.dart';

RemoteEditSession s(RemoteEditStatus st, {String? msg}) => RemoteEditSession(
      id: 'e1',
      remotePath: '/srv/app.conf',
      localTempPath: '/tmp/e1/app.conf',
      baseMtimeMs: 1,
      baseSize: 1,
      mode: 420,
      lastLocalMtimeMs: 1,
      lastLocalSize: 1,
      status: st,
      message: msg,
    );

Widget host(List<RemoteEditSession> sessions, {
  void Function(String)? onFinish,
  void Function(String, ConflictChoice)? onResolve,
}) =>
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: RemoteEditPanel(
          sessions: sessions,
          onFinish: onFinish ?? (_) {},
          onResolve: onResolve ?? (_, __) {},
        ),
      ),
    );

void main() {
  testWidgets('empty → nothing', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(find.byType(RemoteEditPanel), findsOneWidget);
    expect(find.textContaining('app.conf'), findsNothing);
  });

  testWidgets('watching row shows file name + Bitir; finish fires', (tester) async {
    var finished = '';
    await tester.pumpWidget(
      host([s(RemoteEditStatus.watching)], onFinish: (id) => finished = id),
    );
    expect(find.textContaining('app.conf'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bitir'));
    expect(finished, 'e1');
  });

  testWidgets('conflict row shows three resolve actions; overwrite fires', (tester) async {
    ConflictChoice? chosen;
    await tester.pumpWidget(
      host([s(RemoteEditStatus.conflict, msg: 'Uzaktaki dosya değişti')],
          onResolve: (_, c) => chosen = c),
    );
    expect(find.textContaining('değişti'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Uzağı ez'));
    expect(chosen, ConflictChoice.overwriteRemote);
  });

  testWidgets('conflict action "Farklı kaydet" fires saveAsLocal', (tester) async {
    ConflictChoice? chosen;
    await tester.pumpWidget(
      host([s(RemoteEditStatus.conflict, msg: 'Uzaktaki dosya değişti')],
          onResolve: (_, c) => chosen = c),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Farklı kaydet'));
    expect(chosen, ConflictChoice.saveAsLocal);
  });

  testWidgets('conflict action "Devam" fires keepEditing', (tester) async {
    ConflictChoice? chosen;
    await tester.pumpWidget(
      host([s(RemoteEditStatus.conflict, msg: 'Uzaktaki dosya değişti')],
          onResolve: (_, c) => chosen = c),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Devam'));
    expect(chosen, ConflictChoice.keepEditing);
  });

  testWidgets('message hidden for watching state', (tester) async {
    await tester.pumpWidget(host([s(RemoteEditStatus.watching, msg: 'gizli kalmali')]));
    expect(find.textContaining('gizli kalmali'), findsNothing);
  });
}
