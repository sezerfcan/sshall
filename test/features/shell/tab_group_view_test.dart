import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/tab_group_view.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/context_ext.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: child),
  );

  const tabs = {
    't1': ShellTab(id: 't1', kind: TabKind.sftp, title: 'SFTP'),
    't0': ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1'),
  };

  TabGroupView view({
    bool isActiveGroup = true,
    bool isDragging = false,
    void Function()? onActivateGroup,
  }) => TabGroupView(
    group: const TabGroup(id: 'g0', tabIds: ['t1', 't0'], activeTabId: 't0'),
    tabs: tabs,
    isActiveGroup: isActiveGroup,
    canReopen: false,
    statusFor: (_) => null,
    canReconnectFor: (_) => false,
    contentBuilder: (t) => Text('content_${t.id}'),
    onSelect: (_) {},
    onAction: (_, __) {},
    onRenameTab: (_, __) {},
    onNewTab: () {},
    onSplitRight: () {},
    canMerge: false,
    onDrop: (_, __, ___) {},
    onDragStart: (_) {},
    onDragEnd: () {},
    onDoubleTapEmpty: () {},
    onActivateGroup: onActivateGroup ?? () {},
    isDragging: isDragging,
    onBodyDrop: (_, __) {},
  );

  Border bodyBorder(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byKey(const Key('groupBody_g0')),
    );
    return (container.decoration as BoxDecoration).border! as Border;
  }

  testWidgets(
    'IndexedStack shows the active tab content; inactive kept alive',
    (tester) async {
      await tester.pumpWidget(host(view()));
      expect(find.text('content_t0'), findsOneWidget);
      // Inactive tab is still mounted (state preserved) but offstage in the
      // IndexedStack — assert with skipOffstage: false.
      expect(find.text('content_t1', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets('active group body carries a ~2px accent border (ADR 0036 D5)', (
    tester,
  ) async {
    await tester.pumpWidget(host(view(isActiveGroup: true)));
    final accent = tester.element(find.byType(TabGroupView)).c.accent;
    final border = bodyBorder(tester);
    expect(border.top.width, 2);
    expect(border.top.color, accent);
  });

  testWidgets(
    'inactive group body carries a neutral 1px border (ADR 0036 D5)',
    (tester) async {
      await tester.pumpWidget(host(view(isActiveGroup: false)));
      final ctx = tester.element(find.byType(TabGroupView));
      final border = bodyBorder(tester);
      expect(border.top.width, 1);
      expect(border.top.color, ctx.c.border);
      expect(border.top.color, isNot(ctx.c.accent));
    },
  );

  testWidgets('tapping an inactive group body fires onActivateGroup (D5)', (
    tester,
  ) async {
    var activated = 0;
    await tester.pumpWidget(
      host(view(isActiveGroup: false, onActivateGroup: () => activated++)),
    );
    await tester.tap(find.text('content_t0'));
    await tester.pump();
    expect(activated, 1);
  });

  testWidgets('5-zone body drop overlay survives the border (ADR 0019 kept)', (
    tester,
  ) async {
    await tester.pumpWidget(host(view(isDragging: true)));
    // The drop target overlay is still mounted while dragging (the border does
    // not replace it).
    expect(find.byType(DragTarget<TabDragData>), findsWidgets);
    // And the body still has the active accent border around it.
    expect(bodyBorder(tester).top.width, 2);
  });
}
