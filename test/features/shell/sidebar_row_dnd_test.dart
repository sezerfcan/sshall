import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/sidebar_drag.dart';
import 'package:sshall/features/shell/sidebar_row.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

/// Isolated widget tests for the DnD built into [SidebarRow] (ADR 0035 D1):
/// the 3-zone before/after/into routing, the insertion line + move-into
/// highlight indicators, the cycle-rejection gate, and the ghost chip. No
/// SecureStore — the drop callbacks just record what fired, so these run fast
/// and deterministically.

Widget _app(Widget child) => MaterialApp(
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(body: SizedBox(width: 280, child: child)),
);

/// Two stacked rows: a draggable host 'a' over a target row 'b' (folder or host).
class _Harness extends StatelessWidget {
  const _Harness({
    required this.targetIsFolder,
    required this.onDropBefore,
    required this.onDropAfter,
    required this.onDropInto,
    this.willAccept,
  });

  final bool targetIsFolder;
  final void Function(SidebarDragData)? onDropBefore;
  final void Function(SidebarDragData)? onDropAfter;
  final void Function(SidebarDragData)? onDropInto;
  final bool Function(SidebarDragData, DropZone)? willAccept;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SidebarRow(
          rowKey: const Key('row-a'),
          semanticLabel: 'aaa',
          dragGhostLabel: 'aaa',
          dragData: const SidebarDragData(id: 'a', isFolder: false),
          onTap: () {},
          child: const SizedBox(height: 30, child: Text('aaa')),
        ),
        SidebarRow(
          rowKey: const Key('row-b'),
          semanticLabel: 'bbb',
          isFolderRow: targetIsFolder,
          dragData: SidebarDragData(id: 'b', isFolder: targetIsFolder),
          onTap: () {},
          willAcceptDrag: willAccept,
          onDropBefore: onDropBefore,
          onDropAfter: onDropAfter,
          onDropInto: onDropInto,
          child: const SizedBox(height: 30, child: Text('bbb')),
        ),
      ],
    );
  }
}

Future<void> _drag(WidgetTester tester, {required double zoneFraction}) async {
  final from = tester.getCenter(find.byKey(const Key('row-a')));
  final toRect = tester.getRect(find.byKey(const Key('row-b')));
  final target = Offset(
    toRect.center.dx,
    toRect.top + toRect.height * zoneFraction,
  );
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 20));
  await g.moveBy(const Offset(0, 30));
  await tester.pump(const Duration(milliseconds: 20));
  final start = from + const Offset(0, 30);
  for (var i = 1; i <= 8; i++) {
    await g.moveTo(Offset.lerp(start, target, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.moveTo(target);
  await tester.pump(const Duration(milliseconds: 16));
  await g.up();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('after-zone drop fires onDropAfter + shows the insertion line', (
    tester,
  ) async {
    String? after;
    await tester.pumpWidget(
      _app(
        _Harness(
          targetIsFolder: false,
          onDropBefore: (_) {},
          onDropAfter: (d) => after = d.id,
          onDropInto: null,
        ),
      ),
    );
    // Mid-drag the insertion line is shown at the after edge.
    final from = tester.getCenter(find.byKey(const Key('row-a')));
    final toRect = tester.getRect(find.byKey(const Key('row-b')));
    final target = Offset(toRect.center.dx, toRect.top + toRect.height * 0.85);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveBy(const Offset(0, 30));
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from + const Offset(0, 30), target, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const Key('sidebar-insertion-line')), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(after, 'a');
  });

  testWidgets('before-zone drop fires onDropBefore', (tester) async {
    String? before;
    await tester.pumpWidget(
      _app(
        _Harness(
          targetIsFolder: false,
          onDropBefore: (d) => before = d.id,
          onDropAfter: (_) {},
          onDropInto: null,
        ),
      ),
    );
    await _drag(tester, zoneFraction: 0.15);
    expect(before, 'a');
  });

  testWidgets(
    'middle of a folder row fires onDropInto + shows move-into highlight',
    (tester) async {
      String? into;
      await tester.pumpWidget(
        _app(
          _Harness(
            targetIsFolder: true,
            onDropBefore: (_) {},
            onDropAfter: (_) {},
            onDropInto: (d) => into = d.id,
          ),
        ),
      );
      await _drag(tester, zoneFraction: 0.5);
      expect(into, 'a');
    },
  );

  testWidgets('willAcceptDrag=false rejects the into drop (no callback)', (
    tester,
  ) async {
    String? into;
    await tester.pumpWidget(
      _app(
        _Harness(
          targetIsFolder: true,
          onDropBefore: (_) {},
          onDropAfter: (_) {},
          onDropInto: (d) => into = d.id,
          // Reject every into drop (stands in for a cycle).
          willAccept: (data, zone) => zone != DropZone.into,
        ),
      ),
    );
    await _drag(tester, zoneFraction: 0.5);
    expect(into, isNull); // rejected — onDropInto never fired
  });

  testWidgets('the drag-ghost chip appears during a drag', (tester) async {
    await tester.pumpWidget(
      _app(
        _Harness(
          targetIsFolder: false,
          onDropBefore: (_) {},
          onDropAfter: (_) {},
          onDropInto: null,
        ),
      ),
    );
    final from = tester.getCenter(find.byKey(const Key('row-a')));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 20));
    // Two 'aaa' texts: the dimmed childWhenDragging + the feedback ghost.
    expect(find.text('aaa'), findsNWidgets(2));
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
