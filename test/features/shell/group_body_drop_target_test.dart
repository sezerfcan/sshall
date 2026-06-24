import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/group_body_drop_target.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/split_tree.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  group('zoneFor', () {
    const size = Size(400, 300);
    test('the central box is the center (move) zone', () {
      expect(zoneFor(size, const Offset(200, 150)), DropZone.center);
    });
    test('the left strip is the left zone', () {
      expect(zoneFor(size, const Offset(20, 150)), DropZone.left);
    });
    test('the right strip is the right zone', () {
      expect(zoneFor(size, const Offset(380, 150)), DropZone.right);
    });
    test('the top strip is the top zone', () {
      expect(zoneFor(size, const Offset(200, 10)), DropZone.top);
    });
    test('the bottom strip is the bottom zone', () {
      expect(zoneFor(size, const Offset(200, 290)), DropZone.bottom);
    });
    test('a degenerate size falls back to center', () {
      expect(zoneFor(Size.zero, Offset.zero), DropZone.center);
    });
  });

  group('GroupBodyDropTarget widget', () {
    Widget harness({
      required bool dragActive,
      required void Function(TabDragData, DropZone) onDrop,
    }) {
      return MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Column(
            children: [
              Draggable<TabDragData>(
                data: const TabDragData('t', 'src'),
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: const SizedBox(width: 40, height: 20),
                child: Container(
                  key: const Key('src'),
                  width: 40,
                  height: 20,
                  color: const Color(0xFF333333),
                ),
              ),
              SizedBox(
                key: const Key('dropbody'),
                width: 400,
                height: 300,
                child: GroupBodyDropTarget(
                  groupId: 'g',
                  dragActive: dragActive,
                  onDrop: onDrop,
                  child: const ColoredBox(color: Color(0xFF111111)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('no overlay DragTarget when no drag is active', (tester) async {
      await tester.pumpWidget(harness(dragActive: false, onDrop: (_, __) {}));
      expect(find.byType(DragTarget<TabDragData>), findsNothing);
    });

    testWidgets('dropping on the left half reports the left zone', (
      tester,
    ) async {
      DropZone? zone;
      await tester.pumpWidget(
        harness(dragActive: true, onDrop: (_, z) => zone = z),
      );
      final body = tester.getRect(find.byKey(const Key('dropbody')));
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('src'))),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveTo(body.centerLeft + const Offset(20, 0));
      await tester.pump();
      // A preview label is shown while hovering a zone (discoverability).
      expect(find.text('Sola böl'), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(zone, DropZone.left);
    });

    testWidgets('dropping on the bottom half reports the bottom zone', (
      tester,
    ) async {
      DropZone? zone;
      await tester.pumpWidget(
        harness(dragActive: true, onDrop: (_, z) => zone = z),
      );
      final body = tester.getRect(find.byKey(const Key('dropbody')));
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('src'))),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveTo(body.bottomCenter - const Offset(0, 20));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(zone, DropZone.bottom);
    });
  });
}
