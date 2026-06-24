import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/shell_tab_bar.dart';
import 'package:sshall/features/shell/tab_context_menu.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: SizedBox(width: 600, child: child)),
  );

  const tabs = {
    // A pinned tab renders compact (icon-only): its title shows only in the
    // overflow menu — handy for the overflow assertions below.
    'p0': ShellTab(
      id: 'p0',
      kind: TabKind.terminal,
      title: 'pinned-host',
      pinned: true,
    ),
    't0': ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1:22'),
  };
  const group = TabGroup(id: 'g0', tabIds: ['p0', 't0'], activeTabId: 't0');

  ShellTabBar bar({
    void Function(String)? onSelect,
    void Function(TabAction, String)? onAction,
    void Function()? onDoubleTapEmpty,
    void Function()? onNewTab,
    void Function()? onSplitRight,
    bool canSplit = true,
    bool canReopen = false,
  }) => ShellTabBar(
    group: group,
    tabs: tabs,
    isActiveGroup: true,
    canReopen: canReopen,
    statusFor: (_) => null,
    canReconnectFor: (_) => false,
    onSelect: onSelect ?? (_) {},
    onAction: onAction ?? (_, __) {},
    onRenameTab: (_, __) {},
    onNewTab: onNewTab ?? () {},
    onSplitRight: onSplitRight ?? () {},
    canSplit: canSplit,
    canMerge: false,
    onDrop: (_, __, ___) {},
    onDragStart: (_) {},
    onDragEnd: () {},
    onDoubleTapEmpty: onDoubleTapEmpty ?? () {},
  );

  testWidgets('renders a pill per tab (terminal shows its title)', (
    tester,
  ) async {
    await tester.pumpWidget(host(bar()));
    expect(find.byKey(const Key('tab_p0')), findsOneWidget);
    expect(find.byKey(const Key('tab_t0')), findsOneWidget);
    // Normal pill shows its title; the pinned pill is compact but now keeps a
    // short (truncated) title too (ADR 0036 D4) — no longer anonymous.
    expect(find.text('web1:22'), findsOneWidget);
    expect(find.text('pinned-host'), findsOneWidget);
  });

  testWidgets('narrow strip renders pills icon-only (title via tooltip)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(body: SizedBox(width: 180, child: bar())),
      ),
    );
    await tester.pump();
    // At this panel width pills collapse to icon-only (ADR 0021): the title is
    // not painted inline...
    expect(find.text('web1:22'), findsNothing);
    // ...but stays reachable via the pill's tooltip (§9), and the pill remains.
    expect(find.byTooltip('web1:22'), findsOneWidget);
    expect(find.byKey(const Key('tab_t0')), findsOneWidget);
  });

  testWidgets('tapping a tab calls onSelect', (tester) async {
    String? selected;
    await tester.pumpWidget(host(bar(onSelect: (id) => selected = id)));
    await tester.tap(find.byKey(const Key('tab_t0')));
    expect(selected, 't0');
  });

  testWidgets('right-click opens the context menu with the expected items', (
    tester,
  ) async {
    await tester.pumpWidget(host(bar(canReopen: true)));
    await tester.tap(
      find.byKey(const Key('tab_t0')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Kapat'), findsOneWidget);
    expect(find.text('Diğerlerini Kapat'), findsOneWidget);
    expect(find.text('Sağdakileri Kapat'), findsOneWidget);
    expect(find.text('Tümünü Kapat'), findsOneWidget);
    expect(find.text('Sabitle'), findsOneWidget);
    expect(find.text('Sağa Böl'), findsOneWidget);
    expect(find.text('Diğer Gruba Taşı'), findsOneWidget);
    expect(find.text('Kapatılan Sekmeyi Geri Aç'), findsOneWidget);
  });

  testWidgets('selecting "Kapat" from the menu fires onAction(close)', (
    tester,
  ) async {
    TabAction? action;
    String? id;
    await tester.pumpWidget(
      host(
        bar(
          onAction: (a, i) {
            action = a;
            id = i;
          },
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('tab_t0')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(action, TabAction.close);
    expect(id, 't0');
  });

  testWidgets('overflow menu lists all tabs and selecting one calls onSelect', (
    tester,
  ) async {
    String? selected;
    // A narrow strip forces overflow so the caret is shown (ADR 0036 D7) and the
    // dropdown lists every tab.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: bar(onSelect: (id) => selected = id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tabOverflow_g0')));
    await tester.pumpAndSettle();
    // The overflow menu lists every tab; select the pinned one from the popup.
    final menuItem = find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text('pinned-host'),
    );
    expect(menuItem, findsOneWidget);
    await tester.tap(menuItem);
    await tester.pumpAndSettle();
    expect(selected, 'p0');
  });

  testWidgets('the "+" new-tab button is present and triggers onNewTab', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(host(bar(onNewTab: () => fired++)));
    await tester.pumpAndSettle();
    final addBtn = find.byKey(const Key('newTab_g0'));
    expect(addBtn, findsOneWidget);
    expect(find.byTooltip('Yeni sekme (⌘T)'), findsOneWidget);
    await tester.tap(addBtn);
    await tester.pump();
    expect(fired, 1);
  });

  testWidgets('the split-right button is present and triggers onSplitRight', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(
      host(bar(onSplitRight: () => fired++, canSplit: true)),
    );
    await tester.pumpAndSettle();
    final splitBtn = find.byKey(const Key('splitRight_g0'));
    expect(splitBtn, findsOneWidget);
    expect(find.byTooltip('Sağa böl (⌘\\)'), findsOneWidget);
    await tester.tap(splitBtn);
    await tester.pump();
    expect(fired, 1);
  });

  testWidgets('split button is disabled when canSplit is false', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(
      host(bar(onSplitRight: () => fired++, canSplit: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('splitRight_g0')));
    await tester.pump();
    expect(fired, 0); // disabled → no-op
  });

  testWidgets('overflow caret is HIDDEN when the strip does not overflow', (
    tester,
  ) async {
    // A wide strip (600px) with two pills fits — no overflow.
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tabOverflow_g0')), findsNothing);
  });

  testWidgets('overflow caret is SHOWN when the strip overflows', (
    tester,
  ) async {
    // Many tabs in a narrow strip overflow → caret appears.
    final many = <String, ShellTab>{};
    final ids = <String>[];
    for (var i = 0; i < 12; i++) {
      final id = 'm$i';
      many[id] = ShellTab(
        id: id,
        kind: TabKind.terminal,
        title: 'a-long-tab-title-$i',
      );
      ids.add(id);
    }
    final manyGroup = TabGroup(id: 'g0', tabIds: ids, activeTabId: ids.first);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: ShellTabBar(
              group: manyGroup,
              tabs: many,
              isActiveGroup: true,
              canReopen: false,
              statusFor: (_) => null,
              canReconnectFor: (_) => false,
              onSelect: (_) {},
              onAction: (_, __) {},
              onRenameTab: (_, __) {},
              onNewTab: () {},
              onSplitRight: () {},
              canSplit: true,
              canMerge: false,
              onDrop: (_, __, ___) {},
              onDragStart: (_) {},
              onDragEnd: () {},
              onDoubleTapEmpty: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tabOverflow_g0')), findsOneWidget);
  });

  testWidgets('double-tapping empty strip space calls onDoubleTapEmpty', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(host(bar(onDoubleTapEmpty: () => fired++)));
    // Double-tap far to the right, past the pills, on empty strip space.
    await tester.tapAt(const Offset(450, 23));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(450, 23));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fired, 1);
  });
}
