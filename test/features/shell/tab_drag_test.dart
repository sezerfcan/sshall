import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/group_body_drop_target.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/shell_tab_bar.dart';
import 'package:sshall/features/shell/tab_context_menu.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/theme/app_colors.dart';

class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  @override
  Stream<WorkerEvent> get events => _c.stream;
  @override
  WorkerEvent? get currentLifecycle => null;
  @override
  void sendInput(Uint8List data) {}
  @override
  void resize(int w, int h, int pw, int ph) {}
  @override
  void decideHostKey(bool accept) {}
  @override
  Uint8List takeOutputBacklog() => Uint8List(0);
  @override
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}

/// A minimal harness that wires the REAL [ShellTabBar] (strip drops) and
/// [GroupBodyDropTarget] (body directional drops) to a real [TabsController],
/// mirroring the AppShell drag wiring without its heavy dependencies. Drag
/// interactions are asserted against controller state.
Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: Consumer(
          builder: (ctx, ref, _) {
            final ts = ref.watch(tabsControllerProvider);
            final n = ref.read(tabsControllerProvider.notifier);
            final dragging = ref.watch(draggingTabProvider) != null;

            Widget strip(TabGroup g) => ShellTabBar(
              group: g,
              tabs: ts.tabs,
              isActiveGroup: g.id == ts.activeGroupId,
              canReopen: n.canReopenClosed,
              statusFor: (id) => n.controllerFor(id)?.status,
              canReconnectFor: (id) =>
                  n.controllerFor(id)?.canReconnect ?? false,
              onSelect: (id) => n.setActive(g.id, id),
              onAction: (_, __) {},
              onRenameTab: (id, title) => n.setTabTitle(id, title),
              onNewTab: () {},
              onSplitRight: () => n.splitRight(),
              canSplit: g.tabIds.length >= 2,
              canMerge: ts.groups.length >= 2,
              onDrop: (d, grp, idx) => n.moveTab(d.tabId, grp, idx),
              onDragStart: (id) =>
                  ref.read(draggingTabProvider.notifier).state = id,
              onDragEnd: () =>
                  ref.read(draggingTabProvider.notifier).state = null,
              onDoubleTapEmpty: () {},
            );

            Widget group(TabGroup g) => Column(
              children: [
                SizedBox(height: 46, child: strip(g)),
                Expanded(
                  child: GroupBodyDropTarget(
                    groupId: g.id,
                    dragActive: dragging,
                    onDrop: (data, zone) =>
                        n.splitTabToGroup(data.tabId, g.id, zone),
                    child: Container(key: Key('body_${g.id}')),
                  ),
                ),
              ],
            );

            return Row(
              children: [for (final g in ts.groups) Expanded(child: group(g))],
            );
          },
        ),
      ),
    ),
  );
}

/// Harness for drag-to-detach (ADR 0021): one group's strip with detach enabled
/// and a recorder for the [TabAction]s the strip reports. The body is a plain
/// box so the strip is the only in-window drop target — a release anywhere else
/// (incl. beyond the window bounds) is not accepted by a target.
Widget _detachHarness(
  ProviderContainer container,
  List<(TabAction, String)> recorded, {
  bool canDetach = true,
  Size size = const Size(800, 600),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) {
              final ts = ref.watch(tabsControllerProvider);
              final n = ref.read(tabsControllerProvider.notifier);
              final g = ts.groups.first;
              return Column(
                children: [
                  SizedBox(
                    height: 46,
                    child: ShellTabBar(
                      group: g,
                      tabs: ts.tabs,
                      isActiveGroup: true,
                      canReopen: n.canReopenClosed,
                      canDetach: canDetach,
                      statusFor: (id) => n.controllerFor(id)?.status,
                      canReconnectFor: (id) =>
                          n.controllerFor(id)?.canReconnect ?? false,
                      onSelect: (id) => n.setActive(g.id, id),
                      onAction: (a, id) => recorded.add((a, id)),
                      onRenameTab: (id, title) => n.setTabTitle(id, title),
                      onNewTab: () {},
                      onSplitRight: () => n.splitRight(),
                      canSplit: g.tabIds.length >= 2,
                      canMerge: ts.groups.length >= 2,
                      onDrop: (d, grp, idx) => n.moveTab(d.tabId, grp, idx),
                      onDragStart: (id) =>
                          ref.read(draggingTabProvider.notifier).state = id,
                      onDragEnd: () =>
                          ref.read(draggingTabProvider.notifier).state = null,
                      onDoubleTapEmpty: () {},
                    ),
                  ),
                  const Expanded(child: SizedBox.expand()),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  late ProviderContainer container;
  late TabsController c;
  setUp(() {
    container = ProviderContainer();
    c = container.read(tabsControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  TabsState st() => container.read(tabsControllerProvider);

  testWidgets('drag a tab within a group reorders it', (tester) async {
    final t0 = c.openTerminal(_FakeSession(), 'a');
    final t1 = c.openTerminal(_FakeSession(), 'b'); // order: home, a, b
    await tester.pumpWidget(_harness(container));
    await tester.pump();

    // Drag "a" far to the right, past "b", to the end of the strip.
    await tester.drag(
      find.byKey(Key('tab_$t0')),
      const Offset(300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    final order = st().groups.first.tabIds;
    expect(order.last, t0, reason: 'a moved to the end');
    expect(order.indexOf(t1) < order.indexOf(t0), isTrue);
  });

  testWidgets('drag a tab onto another group moves it there', (tester) async {
    final t0 = c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b');
    c.splitRight(); // b -> right group; left = home, a
    await tester.pumpWidget(_harness(container));
    await tester.pump();

    final rightGroupId = st().groups[1].id;
    // Drag "a" from the left strip into the right group's strip.
    await tester.drag(
      find.byKey(Key('tab_$t0')),
      const Offset(500, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    final right = st().groups.firstWhere((g) => g.id == rightGroupId);
    expect(right.tabIds.contains(t0), isTrue);
  });

  testWidgets('dropping on a group body LEFT zone splits horizontally', (
    tester,
  ) async {
    final t0 = c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b'); // home, a, b in one group
    await tester.pumpWidget(_harness(container));
    await tester.pump();
    expect(st().groups.length, 1);

    final start = tester.getCenter(find.byKey(Key('tab_$t0')));
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(
      const Offset(0, 60),
    ); // begin drag into the body, reveal zones
    await tester.pump();
    final body = tester.getRect(
      find.byKey(Key('body_${st().groups.first.id}')),
    );
    await g.moveTo(body.centerLeft + const Offset(20, 0));
    await tester.pump();
    expect(find.text('Sola böl'), findsOneWidget);
    await g.up();
    await tester.pump();

    expect(st().groups.length, 2, reason: 'body drop created a new group');
    expect(st().groups.first.tabIds, [t0], reason: 'left split is leftmost');
  });

  testWidgets('dropping on a group body BOTTOM zone splits vertically', (
    tester,
  ) async {
    final t0 = c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b');
    await tester.pumpWidget(_harness(container));
    await tester.pump();

    final start = tester.getCenter(find.byKey(Key('tab_$t0')));
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    final body = tester.getRect(
      find.byKey(Key('body_${st().groups.first.id}')),
    );
    await g.moveTo(body.bottomCenter - const Offset(0, 20));
    await tester.pump();
    expect(find.text('Aşağı böl'), findsOneWidget);
    await g.up();
    await tester.pump();

    expect(st().groups.length, 2);
  });

  // --- drag-to-detach (ADR 0021, extends ADR 0020) ---

  testWidgets('dragging a terminal tab beyond the window detaches it', (
    tester,
  ) async {
    final t0 = c.openTerminal(_FakeSession(), 'web1');
    final recorded = <(TabAction, String)>[];
    await tester.pumpWidget(_detachHarness(container, recorded));
    await tester.pump();

    final start = tester.getCenter(find.byKey(Key('tab_$t0')));
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 20)); // pick the tab up
    await tester.pump();
    await g.moveTo(const Offset(1000, 300)); // beyond the 800px-wide window
    await tester.pump();
    // §9 hint: the drag feedback shows a "move to a new window" badge.
    expect(find.text('Ayrı pencereye taşı'), findsOneWidget);
    await g.up();
    await tester.pump();

    expect(
      recorded,
      contains((TabAction.detachToWindow, t0)),
      reason: 'releasing outside the window tears the tab off',
    );
  });

  testWidgets('releasing inside the window never detaches (reorder intact)', (
    tester,
  ) async {
    final t0 = c.openTerminal(_FakeSession(), 'a');
    c.openTerminal(_FakeSession(), 'b');
    final recorded = <(TabAction, String)>[];
    await tester.pumpWidget(_detachHarness(container, recorded));
    await tester.pump();

    await tester.drag(
      find.byKey(Key('tab_$t0')),
      const Offset(200, 0), // stays within the strip → reorder, not detach
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(
      recorded.where((r) => r.$1 == TabAction.detachToWindow),
      isEmpty,
      reason: 'an in-window drop must not detach',
    );
  });

  testWidgets('non-detachable strip ignores drag-out (no hint, no detach)', (
    tester,
  ) async {
    final t0 = c.openTerminal(_FakeSession(), 'web1');
    final recorded = <(TabAction, String)>[];
    await tester.pumpWidget(
      _detachHarness(container, recorded, canDetach: false),
    );
    await tester.pump();

    final start = tester.getCenter(find.byKey(Key('tab_$t0')));
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveTo(const Offset(1000, 300));
    await tester.pump();
    expect(find.text('Ayrı pencereye taşı'), findsNothing);
    await g.up();
    await tester.pump();

    expect(recorded.where((r) => r.$1 == TabAction.detachToWindow), isEmpty);
  });
}
