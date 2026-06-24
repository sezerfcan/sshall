import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/resizable_split.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  List<double>? captured;

  Widget host({
    required Axis axis,
    required List<double> weights,
    double width = 400,
    double height = 200,
  }) {
    captured = null;
    return MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ResizableSplit(
              axis: axis,
              weights: weights,
              onWeights: (w) => captured = w,
              children: const [
                ColoredBox(color: Color(0xFF111111)),
                ColoredBox(color: Color(0xFF222222)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dragging the handle right grows the left panel weight', (
    tester,
  ) async {
    await tester.pumpWidget(host(axis: Axis.horizontal, weights: [0.5, 0.5]));
    await tester.drag(
      find.byKey(const Key('resizeHandle_0')),
      const Offset(50, 0),
    );
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured![0], greaterThan(0.5));
    expect(captured![0] + captured![1], closeTo(1.0, 1e-9));
  });

  testWidgets('a huge drag is clamped by the minimum panel size', (
    tester,
  ) async {
    await tester.pumpWidget(host(axis: Axis.horizontal, weights: [0.5, 0.5]));
    await tester.drag(
      find.byKey(const Key('resizeHandle_0')),
      const Offset(5000, 0),
    );
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    // available ~= 400 - 6 = 394; min frac ~= 140/394 ~= 0.355; so left <= ~0.645
    expect(
      captured![1],
      greaterThan(0.34),
      reason: 'right panel keeps its min',
    );
    expect(captured![0], lessThan(0.66));
  });

  testWidgets('double-tapping the handle equalizes the branch', (tester) async {
    await tester.pumpWidget(host(axis: Axis.horizontal, weights: [0.8, 0.2]));
    final loc = tester.getCenter(find.byKey(const Key('resizeHandle_0')));
    await tester.tapAt(loc);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(loc);
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured![0], closeTo(0.5, 1e-9));
    expect(captured![1], closeTo(0.5, 1e-9));
  });

  testWidgets('the handle exposes a resize mouse cursor', (tester) async {
    await tester.pumpWidget(host(axis: Axis.horizontal, weights: [0.5, 0.5]));
    final region = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byKey(const Key('resizeHandle_0')),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.resizeColumn);
  });

  testWidgets('a vertical split uses a row-resize cursor', (tester) async {
    await tester.pumpWidget(host(axis: Axis.vertical, weights: [0.5, 0.5]));
    final region = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byKey(const Key('resizeHandle_0')),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.resizeRow);
  });
}
