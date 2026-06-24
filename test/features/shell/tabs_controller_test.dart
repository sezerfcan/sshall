import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/split_tree.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';

class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  int closeCalls = 0;
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
    closeCalls++;
    if (!_c.isClosed) await _c.close();
  }
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

  group('basics (session-only, ADR 0022)', () {
    test('initial state is empty: no tabs, one empty group, no active tab', () {
      expect(st().groups.length, 1);
      expect(st().tabs.length, 0);
      expect(st().activeTab, isNull);
      expect(st().hasSessions, isFalse);
      expect(st().activeGroup.tabIds, isEmpty);
    });

    test('openTerminal appends a terminal tab and makes it active', () {
      final id = c.openTerminal(_FakeSession(), 'web1:22');
      expect(st().tabs[id]!.kind, TabKind.terminal);
      expect(st().activeTab!.id, id);
      expect(st().activeGroup.tabIds.length, 1); // no home tab anymore
      expect(st().hasSessions, isTrue);
      expect(c.controllerFor(id), isNotNull);
    });

    test('openOrFocus(sftp) is a singleton and focuses the existing tab', () {
      c.openOrFocus(TabKind.sftp);
      final firstCount = st().tabs.length;
      c.openTerminal(_FakeSession(), 't'); // move focus away
      c.openOrFocus(TabKind.sftp); // focus existing sftp, no new tab
      expect(st().tabs.length, firstCount + 1); // +1 terminal only
      expect(st().activeTab!.kind, TabKind.sftp);
    });

    test('close moves active to a neighbor', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      expect(st().activeTab!.id, b);
      c.close(b);
      expect(st().tabs.containsKey(b), isFalse);
      expect(st().activeTab!.id, a); // fell back to neighbor
    });

    test('closing the last session returns to the empty welcome state', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      c.close(a);
      expect(st().tabs.length, 0);
      expect(st().activeTab, isNull);
      expect(st().hasSessions, isFalse);
      expect(st().groups.length, 1);
      expect(st().layout, isA<GroupLeaf>());
    });

    test('closeAll disposes terminals and resets to the empty state', () async {
      final s1 = _FakeSession();
      c.openTerminal(s1, 'a');
      c.openOrFocus(TabKind.sftp);
      await c.closeAll();
      expect(st().tabs.length, 0);
      expect(st().activeTab, isNull);
      expect(st().hasSessions, isFalse);
      expect(s1.closeCalls, 1);
    });
  });

  group('rename / titles (ADR 0036 D2/D3)', () {
    test(
      'setTabTitle writes customTitle without touching the default title',
      () {
        final id = c.openTerminal(_FakeSession(), 'web-prod');
        c.setTabTitle(id, 'prod-db');
        expect(st().tabs[id]!.customTitle, 'prod-db');
        expect(st().tabs[id]!.effectiveTitle, 'prod-db');
        expect(st().tabs[id]!.title, 'web-prod'); // derived default unchanged
      },
    );

    test('blank/whitespace setTabTitle clears back to the derived default', () {
      final id = c.openTerminal(_FakeSession(), 'web-prod');
      c.setTabTitle(id, 'renamed');
      expect(st().tabs[id]!.customTitle, 'renamed');
      c.setTabTitle(id, '   ');
      expect(st().tabs[id]!.customTitle, isNull);
      expect(st().tabs[id]!.effectiveTitle, 'web-prod');
    });

    test('setTabTitle on an unknown id is a no-op', () {
      final id = c.openTerminal(_FakeSession(), 'a');
      final before = st();
      c.setTabTitle('nope', 'x');
      expect(st(), same(before)); // identical revision: no mutation
      expect(st().tabs[id]!.customTitle, isNull);
    });

    test('terminal default title is host-derived (never bare "Terminal")', () {
      final id = c.openTerminal(_FakeSession(), 'web-prod');
      expect(st().tabs[id]!.title, 'web-prod');
      expect(st().tabs[id]!.customTitle, isNull);
      expect(st().tabs[id]!.effectiveTitle, 'web-prod');
      expect(st().tabs[id]!.effectiveTitle, isNot('Terminal'));
    });

    test('two fresh tabs get distinct host-derived defaults', () {
      final a = c.openTerminal(_FakeSession(), 'web1:22');
      final b = c.openTerminal(_FakeSession(), 'db1:22');
      expect(st().tabs[a]!.effectiveTitle, isNot(st().tabs[b]!.effectiveTitle));
    });

    test('SFTP default title carries host context ("SFTP · host")', () {
      c.openOrFocus(TabKind.sftp, host: 'prod-box');
      final tab = st().tabs.values.firstWhere((t) => t.kind == TabKind.sftp);
      expect(tab.effectiveTitle, 'SFTP · prod-box');
    });

    test('SFTP with no host falls back to the generic "SFTP"', () {
      c.openOrFocus(TabKind.sftp);
      final tab = st().tabs.values.firstWhere((t) => t.kind == TabKind.sftp);
      expect(tab.effectiveTitle, 'SFTP');
    });
  });

  group('activeSessionTitleProvider derivation (ADR 0039 D1)', () {
    String? title() => container.read(activeSessionTitleProvider);

    test('null on the home / no-session surface (never a fake title)', () {
      expect(st().hasSessions, isFalse);
      expect(title(), isNull);
    });

    test(
      'derives the active tab effectiveTitle (active group → active tab)',
      () {
        c.openTerminal(_FakeSession(), 'web-prod');
        expect(title(), 'web-prod');
      },
    );

    test('follows the active tab, not just the most-recently opened', () {
      final a = c.openTerminal(_FakeSession(), 'web-1');
      c.openTerminal(_FakeSession(), 'db-1');
      expect(title(), 'db-1'); // newest is active
      final g = st().activeGroup.id;
      c.setActive(g, a);
      expect(title(), 'web-1'); // re-derives on activation
    });

    test('reflects a manual rename (customTitle wins over derived)', () {
      final id = c.openTerminal(_FakeSession(), 'web-prod');
      c.setTabTitle(id, 'prod-db');
      expect(title(), 'prod-db');
    });

    test('returns to null after the last session is closed', () {
      final id = c.openTerminal(_FakeSession(), 'web-prod');
      expect(title(), 'web-prod');
      c.close(id);
      expect(title(), isNull);
    });
  });

  group('split (N groups)', () {
    test(
      'splitRight needs >=2 tabs, creates a second group and moves active',
      () {
        c.openTerminal(_FakeSession(), 'a');
        c.openTerminal(_FakeSession(), 'b'); // g0: a, b (active b)
        c.splitRight();
        expect(st().groups.length, 2);
        expect(st().groups[1].tabIds.length, 1); // moved tab
        expect(st().activeGroupId, st().groups[1].id);
      },
    );

    test('splitRight is a no-op with a single tab', () {
      c.openTerminal(_FakeSession(), 'a'); // only one tab
      c.splitRight();
      expect(st().groups.length, 1);
    });

    test('splitRight can create a THIRD group (N-group)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      c.openTerminal(_FakeSession(), 'd'); // a,b,d in g0
      c.setActive(st().activeGroup.id, a);
      c.splitRight(a); // a -> new group; g0 = b,d
      expect(st().groups.length, 2);
      c.setActive(st().groups[0].id, b);
      c.splitRight(b); // g0 has [b,d] (>=2) -> b to another new group
      expect(st().groups.length, 3);
    });

    test('splitTabToGroup(left) inserts a new group before the target', () {
      c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // a,b in g0
      final g0 = st().activeGroup.id;
      c.splitTabToGroup(b, g0, DropZone.left); // b -> new group left of g0
      expect(st().groups.length, 2);
      expect(st().groups.first.tabIds, [b]); // DFS-leftmost is the new group
    });

    test('emptied group is removed (auto-unsplit)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b'); // a,b
      c.splitRight(); // b -> right group; g0 = a
      expect(st().groups.length, 2);
      c.moveToOtherGroup(a); // a -> right; left empties -> unsplit
      expect(st().groups.length, 1);
      expect(st().tabs.containsKey(a), isTrue);
    });
  });

  group('reorder / move (drag-and-drop core)', () {
    test('moveTab reorders within a group (rendered-order slot)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // order: a, b
      final g = st().activeGroup.id;
      c.moveTab(b, g, 0); // move b to the front
      expect(st().activeGroup.tabIds, [b, a]);
    });

    test('moveTab moves a tab across groups and activates it there', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      c.openTerminal(_FakeSession(), 'c'); // a,b,c (active c)
      c.splitRight(); // c -> right group; left = a,b
      final left = st().groups[0].id;
      final right = st().groups[1].id;
      c.moveTab(a, right, st().groups[1].tabIds.length);
      expect(
        st().groups.firstWhere((g) => g.id == right).tabIds.contains(a),
        isTrue,
      );
      expect(st().activeGroupId, right);
      expect(st().activeTab!.id, a);
      // left still has b
      expect(st().groups.firstWhere((g) => g.id == left).tabIds, [b]);
    });

    test('an unpinned tab cannot be moved ahead of a pinned tab (clamp)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // a, b
      c.togglePin(a); // a pinned -> [a, b]
      final g = st().activeGroup.id;
      c.moveTab(b, g, 0); // try to drop before pinned a
      expect(st().activeGroup.tabIds.first, a); // pinned a still first
      expect(st().activeGroup.tabIds, [a, b]);
    });
  });

  group('pinning', () {
    test('togglePin moves a tab into the pinned region', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // a, b
      c.togglePin(b);
      expect(st().tabs[b]!.pinned, isTrue);
      // pinned region = [b]; unpinned = [a]
      expect(st().activeGroup.tabIds, [b, a]);
    });

    test('unpin moves the tab back to the start of the unpinned region', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // a, b
      c.togglePin(a); // a(pinned), b
      expect(st().activeGroup.tabIds, [a, b]);
      c.togglePin(a); // unpin -> a moves to start of unpinned region
      expect(st().tabs[a]!.pinned, isFalse);
      expect(st().activeGroup.tabIds, [a, b]);
    });

    test('closeOthers keeps pinned + the target', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      final d = c.openTerminal(_FakeSession(), 'd'); // a,b,d
      c.togglePin(b);
      c.closeOthers(d); // closes a; keeps b(pinned) + d
      final ids = st().activeGroup.tabIds;
      expect(ids.contains(b), isTrue); // pinned survives
      expect(ids.contains(d), isTrue); // the target survives
      expect(ids.contains(a), isFalse);
    });

    test('closeToRight closes only closable tabs after the target', () {
      c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      final d = c.openTerminal(_FakeSession(), 'd'); // a,b,d
      c.closeToRight(b); // closes d only
      expect(st().tabs.containsKey(d), isFalse);
      expect(st().tabs.containsKey(b), isTrue);
    });
  });

  group('reopen closed', () {
    test('reopen brings back an SFTP session via openOrFocus', () {
      c.openOrFocus(TabKind.sftp);
      final sftpId = st().activeTab!.id;
      c.close(sftpId);
      expect(st().tabs.values.any((t) => t.kind == TabKind.sftp), isFalse);
      expect(c.canReopenClosed, isTrue);
      c.reopenClosed();
      expect(st().tabs.values.any((t) => t.kind == TabKind.sftp), isTrue);
    });

    test('reopen invokes the stored terminal reopen thunk', () {
      var reopened = 0;
      final id = c.openTerminal(_FakeSession(), 't', reopen: () => reopened++);
      c.close(id);
      c.reopenClosed();
      expect(reopened, 1);
    });

    test('reopen on an empty stack is a no-op', () {
      expect(c.canReopenClosed, isFalse);
      c.reopenClosed(); // must not throw
      expect(st().tabs.length, 0);
    });
  });

  group('keyboard navigation helpers', () {
    test('cycleMru toggles to the previously-active tab', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // active b; MRU: b,a
      expect(st().activeTab!.id, b);
      c.cycleMru(true); // -> a (previous in MRU)
      expect(st().activeTab!.id, a);
      c.cycleMru(true); // -> wraps back to b
      expect(st().activeTab!.id, b);
    });

    test('a normal activation ends the MRU cycle (commit)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      c.cycleMru(true); // -> a
      c.setActive(st().activeGroup.id, b); // commit: b to MRU front
      c.cycleMru(true); // from fresh cycle -> previous (a)
      expect(st().activeTab!.id, a);
    });

    test('activateRelativeInActiveGroup wraps around', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // a,b active b
      c.activateRelativeInActiveGroup(1); // wrap to a
      expect(st().activeTab!.id, a);
      c.activateRelativeInActiveGroup(-1); // back to b
      expect(st().activeTab!.id, b);
    });

    test('focusGroupByIndex switches the active group', () {
      c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b');
      c.splitRight(); // 2 groups
      c.focusGroupByIndex(0);
      expect(st().activeGroupId, st().groups[0].id);
      c.focusGroupByIndex(1);
      expect(st().activeGroupId, st().groups[1].id);
      c.focusGroupByIndex(9); // out of range -> no-op
      expect(st().activeGroupId, st().groups[1].id);
    });
  });

  group('split tree layout (ADR 0019)', () {
    test('initial layout is a single leaf for the empty group', () {
      expect(st().layout, isA<GroupLeaf>());
      expect((st().layout as GroupLeaf).groupId, st().groups.first.id);
    });

    test('layout group set always equals the groups set (invariant)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b');
      c.splitRight(); // 2 groups
      c.splitTabToGroup(a, st().activeGroup.id, DropZone.bottom);
      expect(st().layout.groupIds, st().groups.map((g) => g.id).toSet());
    });

    test('splitTabToGroup(bottom) makes a vertical branch', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b'); // a,b in g0
      final g0 = st().activeGroup.id;
      c.splitTabToGroup(a, g0, DropZone.bottom);
      expect(st().layout, isA<SplitBranch>());
      expect((st().layout as SplitBranch).axis, SplitAxis.vertical);
      expect(st().groups.length, 2);
    });

    test('center drop zone moves into the target group (no split)', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b');
      c.splitRight(); // b -> right group g1; left = a
      final right = st().groups[1].id;
      c.splitTabToGroup(a, right, DropZone.center); // center == move
      expect(st().groups.length, 1); // a's group emptied -> collapse to 1
      expect(st().groups.first.tabIds.contains(a), isTrue);
    });

    test('splitting a single-tab group against itself is a no-op', () {
      c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b');
      c.splitRight(); // active(b) alone in the right group g1
      final g1 = st().groups[1].id;
      final activeId = st().activeTab!.id;
      c.splitTabToGroup(activeId, g1, DropZone.right); // would vanish -> no-op
      expect(st().groups.length, 2);
    });

    test('groups stay ordered by DFS leaf order', () {
      final a = c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b');
      c.openTerminal(_FakeSession(), 'd'); // a,b,d
      c.setActive(st().activeGroup.id, a);
      c.splitRight(a); // H[g0(b,d), gA(a)]
      c.setActive(st().groups[0].id, b);
      c.splitRight(b); // H[g0(d), gB(b), gA(a)]
      expect(st().groups.length, 3);
      expect(
        st().groups.map((g) => g.id).toList(),
        orderedLeafIds(st().layout),
      );
    });

    test('setLayoutWeights updates the addressed branch weights', () {
      c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b');
      c.splitRight(); // root H[g0, g1]
      c.setLayoutWeights(const [], [3, 1]);
      final b = st().layout as SplitBranch;
      expect(b.weights[0], closeTo(0.75, 1e-9));
      expect(b.weights[1], closeTo(0.25, 1e-9));
    });

    test('closeAll resets the layout to a single leaf', () async {
      c.openTerminal(_FakeSession(), 'a');
      c.openTerminal(_FakeSession(), 'b');
      c.splitRight();
      expect(st().layout, isA<SplitBranch>());
      await c.closeAll();
      expect(st().layout, isA<GroupLeaf>());
    });
  });

  group('detach / redock to a separate window (ADR 0020)', () {
    test('detach hides the tab but keeps the live session alive', () {
      final s = _FakeSession();
      final id = c.openTerminal(s, 'a');
      c.detachTab(id);
      expect(st().tabs.containsKey(id), isFalse, reason: 'hidden from layout');
      expect(c.isDetached(id), isTrue);
      expect(c.controllerFor(id), isNotNull, reason: 'session stays live');
      expect(s.closeCalls, 0, reason: 'session NOT closed on detach');
    });

    test('redock restores the tab reusing the same controller', () {
      final id = c.openTerminal(_FakeSession(), 'a');
      final ctrl = c.controllerFor(id);
      c.detachTab(id);
      c.redockTab(id);
      expect(st().tabs.containsKey(id), isTrue);
      expect(c.isDetached(id), isFalse);
      expect(c.controllerFor(id), same(ctrl), reason: 'same live session');
      expect(st().activeTab!.id, id);
    });

    test('disposeDetached closes the session', () async {
      final s = _FakeSession();
      final id = c.openTerminal(s, 'a');
      c.detachTab(id);
      await c.disposeDetached(id);
      expect(c.isDetached(id), isFalse);
      expect(c.controllerFor(id), isNull);
      expect(s.closeCalls, 1);
    });

    test('detach removes an emptied group from the layout', () {
      c.openTerminal(_FakeSession(), 'a');
      final b = c.openTerminal(_FakeSession(), 'b'); // a,b (active b)
      c.splitRight(); // b alone in a new right group
      expect(st().groups.length, 2);
      c.detachTab(b); // its group empties -> collapses
      expect(st().groups.length, 1);
      expect(c.isDetached(b), isTrue);
    });

    // A redocked tab must always land in a real, rendered group: present in
    // `tabs`, listed in exactly one group's `tabIds`, AND that group must be a
    // leaf of the layout tree (otherwise the tab exists but never paints —
    // "the tab vanished"). Also asserts the global tree/groups invariant.
    void expectDocked(String tabId) {
      final s = st();
      expect(
        s.tabs.containsKey(tabId),
        isTrue,
        reason: 'redocked tab missing from tabs',
      );
      final owners = s.groups.where((g) => g.tabIds.contains(tabId)).toList();
      expect(
        owners.length,
        1,
        reason: 'redocked tab must belong to exactly one group',
      );
      expect(
        s.layout.groupIds.contains(owners.single.id),
        isTrue,
        reason: 'redocked tab\'s group must be in the layout tree',
      );
      // Global invariant maintained by the controller (ADR 0019).
      expect(
        s.layout.groupIds,
        s.groups.map((g) => g.id).toSet(),
        reason: 'layout.groupIds must equal groups.ids',
      );
    }

    test('detach->redock cycle (single terminal) survives 2+ rounds', () {
      final id = c.openTerminal(_FakeSession(), 'a');
      final ctrl = c.controllerFor(id);
      for (var round = 0; round < 3; round++) {
        c.detachTab(id);
        expect(c.isDetached(id), isTrue, reason: 'round $round detach');
        c.redockTab(id);
        expect(c.isDetached(id), isFalse, reason: 'round $round redock');
        expectDocked(id);
        expect(
          c.controllerFor(id),
          same(ctrl),
          reason: 'round $round: session/scrollback preserved',
        );
        expect(st().activeTab?.id, id, reason: 'round $round: refocused');
      }
    });

    test(
      'detach->redock cycle (split, multiple groups) survives 2+ rounds',
      () {
        final a = c.openTerminal(_FakeSession(), 'a');
        final b = c.openTerminal(_FakeSession(), 'b');
        c.splitRight(); // root H[g0:(a), g1:(b)]
        expect(st().groups.length, 2);
        final ctrl = c.controllerFor(b);
        for (var round = 0; round < 3; round++) {
          c.detachTab(b);
          expect(c.isDetached(b), isTrue, reason: 'round $round detach');
          c.redockTab(b);
          expect(c.isDetached(b), isFalse, reason: 'round $round redock');
          expectDocked(b);
          // The other terminal must remain docked the whole time too.
          expectDocked(a);
          expect(
            c.controllerFor(b),
            same(ctrl),
            reason: 'round $round: session/scrollback preserved',
          );
        }
      },
    );
  });
}
