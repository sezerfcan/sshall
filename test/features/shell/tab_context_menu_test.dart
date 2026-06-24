import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/tab_context_menu.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  TabAction? picked;
  Future<void> openMenu(
    WidgetTester tester, {
    required ShellTab tab,
    required bool canDetach,
    bool canReconnect = false,
    bool canMerge = false,
  }) async {
    picked = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showTabContextMenu(
                    context,
                    const Offset(100, 100),
                    tab: tab,
                    canReopen: false,
                    canSplit: true,
                    canMerge: canMerge,
                    canDetach: canDetach,
                    canReconnect: canReconnect,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  const terminalTab = ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1');
  const sftpTab = ShellTab(id: 's0', kind: TabKind.sftp, title: 'SFTP');

  testWidgets('a terminal tab shows "Ayrı Pencereye Taşı" when detach is on', (
    tester,
  ) async {
    await openMenu(tester, tab: terminalTab, canDetach: true);
    expect(find.text('Ayrı Pencereye Taşı'), findsOneWidget);
  });

  testWidgets('detach item is hidden when detach is unsupported', (
    tester,
  ) async {
    await openMenu(tester, tab: terminalTab, canDetach: false);
    expect(find.text('Ayrı Pencereye Taşı'), findsNothing);
  });

  testWidgets('a non-terminal (SFTP) tab never shows the detach item', (
    tester,
  ) async {
    await openMenu(tester, tab: sftpTab, canDetach: true);
    expect(find.text('Ayrı Pencereye Taşı'), findsNothing);
  });

  testWidgets('a terminal tab offers "Yeniden Bağlan" (ADR 0032 D5)', (
    tester,
  ) async {
    await openMenu(tester, tab: terminalTab, canDetach: true);
    expect(find.text('Yeniden Bağlan'), findsOneWidget);
  });

  testWidgets('an SFTP tab never offers "Yeniden Bağlan"', (tester) async {
    await openMenu(tester, tab: sftpTab, canDetach: true);
    expect(find.text('Yeniden Bağlan'), findsNothing);
  });

  testWidgets('shows "Yeniden Adlandır" and returns rename when picked '
      '(ADR 0036 D2/D8)', (tester) async {
    await openMenu(tester, tab: terminalTab, canDetach: true);
    expect(find.text('Yeniden Adlandır'), findsOneWidget);
    await tester.tap(find.text('Yeniden Adlandır'));
    await tester.pumpAndSettle();
    expect(picked, TabAction.rename);
  });

  testWidgets('"Birleştir" is ENABLED when a split exists and returns unsplit '
      '(ADR 0036 D6)', (tester) async {
    await openMenu(tester, tab: terminalTab, canDetach: true, canMerge: true);
    expect(find.text('Birleştir'), findsOneWidget);
    await tester.tap(find.text('Birleştir'));
    await tester.pumpAndSettle();
    expect(picked, TabAction.unsplit);
  });

  testWidgets('"Birleştir" is DISABLED when no split exists (ADR 0036 D6)', (
    tester,
  ) async {
    await openMenu(tester, tab: terminalTab, canDetach: true, canMerge: false);
    expect(find.text('Birleştir'), findsOneWidget);
    // Disabled menu item: tapping it does not resolve to an action.
    await tester.tap(find.text('Birleştir'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('existing items survive (close / pin / split / move / reopen)', (
    tester,
  ) async {
    await openMenu(tester, tab: terminalTab, canDetach: true);
    expect(find.text('Kapat'), findsOneWidget);
    expect(find.text('Sabitle'), findsOneWidget);
    expect(find.text('Sağa Böl'), findsOneWidget);
    expect(find.text('Diğer Gruba Taşı'), findsOneWidget);
  });
}
