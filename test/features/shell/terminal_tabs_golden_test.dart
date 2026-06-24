import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/shell_tab_bar.dart';
import 'package:sshall/features/shell/tab_group_view.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/app_colors.dart';

/// Golden coverage for the terminal tab strip + split UX (ADR 0036):
///   1. the strip with the visible "+" new-tab + split controls and a pinned
///      tab (icon + pin + short title + status dot — not anonymous),
///   2. the active vs inactive split-pane body border (accent ~2px vs neutral
///      1px, side by side),
///   3. the inline rename editor open inside a pill,
/// in all three themes (night / day / terminal). Regenerate with:
///   flutter test --update-goldens test/features/shell/terminal_tabs_golden_test.dart
/// then run without the flag to confirm they pass.

const _themes = AppThemeId.values;

const _stripTabs = <String, ShellTab>{
  'p0': ShellTab(
    id: 'p0',
    kind: TabKind.terminal,
    title: 'prod-db',
    pinned: true,
  ),
  't0': ShellTab(id: 't0', kind: TabKind.terminal, title: 'web-1'),
  't1': ShellTab(id: 't1', kind: TabKind.sftp, title: 'SFTP · prod-db'),
};
const _stripGroup = TabGroup(
  id: 'g0',
  tabIds: ['p0', 't0', 't1'],
  activeTabId: 't0',
);

ShellTabBar _strip() => ShellTabBar(
  group: _stripGroup,
  tabs: _stripTabs,
  isActiveGroup: true,
  canReopen: true,
  canDetach: true,
  statusFor: (_) => null,
  canReconnectFor: (_) => false,
  onSelect: (_) {},
  onAction: (_, __) {},
  onRenameTab: (_, __) {},
  onNewTab: () {},
  onSplitRight: () {},
  canSplit: true,
  canMerge: true,
  onDrop: (_, __, ___) {},
  onDragStart: (_) {},
  onDragEnd: () {},
  onDoubleTapEmpty: () {},
);

TabGroupView _group({required bool isActiveGroup}) => TabGroupView(
  group: TabGroup(
    id: isActiveGroup ? 'gA' : 'gB',
    tabIds: const ['t0'],
    activeTabId: 't0',
  ),
  tabs: const {
    't0': ShellTab(id: 't0', kind: TabKind.terminal, title: 'web-1'),
  },
  isActiveGroup: isActiveGroup,
  canReopen: false,
  statusFor: (_) => null,
  canReconnectFor: (_) => false,
  contentBuilder: (_) => const ColoredBox(color: Color(0x00000000)),
  onSelect: (_) {},
  onAction: (_, __) {},
  onRenameTab: (_, __) {},
  onNewTab: () {},
  onSplitRight: () {},
  canMerge: true,
  onDrop: (_, __, ___) {},
  onDragStart: (_) {},
  onDragEnd: () {},
  onDoubleTapEmpty: () {},
  onActivateGroup: () {},
  isDragging: false,
  onBodyDrop: (_, __) {},
);

Widget _frame(AppThemeId theme, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: appThemeData(theme),
  home: Scaffold(body: child),
);

void main() {
  for (final theme in _themes) {
    testWidgets('tab strip + controls + pinned — ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(520, 48);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _frame(theme, SizedBox(width: 520, child: _strip())),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(ShellTabBar),
        matchesGoldenFile('goldens/tabs_strip_${theme.name}.png'),
      );
    });

    testWidgets('active vs inactive split-pane border — ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(520, 220);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _frame(
          theme,
          Row(
            children: [
              Expanded(child: _group(isActiveGroup: true)),
              Expanded(child: _group(isActiveGroup: false)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Row).first,
        matchesGoldenFile('goldens/tabs_split_border_${theme.name}.png'),
      );
    });

    testWidgets('inline rename editor open — ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(520, 48);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _frame(theme, SizedBox(width: 520, child: _strip())),
      );
      await tester.pumpAndSettle();

      // Open the inline rename editor on the "web-1" tab via a double-tap on its
      // title region.
      final title = find.byKey(const Key('renameTitle_t0'));
      await tester.tap(title);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('renameField_t0')), findsOneWidget);

      await expectLater(
        find.byType(ShellTabBar),
        matchesGoldenFile('goldens/tabs_rename_${theme.name}.png'),
      );
    });
  }
}
