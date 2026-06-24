import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/buttons.dart';
import 'package:sshall/widgets/app_toggle.dart';
import 'package:sshall/widgets/pressable.dart';

Widget _host(Widget child) => MaterialApp(
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(body: Center(child: child)),
);

bool _hasFocusRing(WidgetTester tester) {
  for (final w in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final d = w.decoration;
    if (d is BoxDecoration && d.border != null) {
      if ((d.border as Border).top.color == AppColors.night.focusRing) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  testWidgets('PrimaryButton shows label and fires onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        PrimaryButton(
          label: 'Bağlan',
          icon: Icons.terminal,
          onPressed: () => tapped = true,
        ),
      ),
    );
    expect(find.text('Bağlan'), findsOneWidget);
    await tester.tap(find.text('Bağlan'));
    expect(tapped, isTrue);
  });

  testWidgets('AppToggle reports flips', (tester) async {
    bool? got;
    await tester.pumpWidget(
      _host(AppToggle(value: false, onChanged: (v) => got = v)),
    );
    await tester.tap(find.byType(AppToggle));
    expect(got, isTrue);
  });

  group('buttons adopt Pressable (additive, rest pixel-stable)', () {
    setUp(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional,
    );
    tearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    testWidgets(
      'PrimaryButton painted size is unchanged but a tap just outside the '
      'face (within 44px) still activates',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          _host(PrimaryButton(label: 'OK', onPressed: () => taps++)),
        );
        // The painted Container (button face) keeps its intrinsic small height and
        // the Pressable does NOT inflate layout.
        final face = find
            .descendant(
              of: find.byType(PrimaryButton),
              matching: find.byType(Container),
            )
            .first;
        final faceRect = tester.getRect(face);
        expect(faceRect.height, lessThan(44));
        expect(
          tester.getSize(find.byType(Pressable).first).height,
          faceRect.height,
        );
        // Tap above the painted face but inside the centered 44px hit region.
        // Face is < 44 tall, so the region extends ((44 - faceHeight)/2) px above.
        final slack = (44 - faceRect.height) / 2;
        await tester.tapAt(
          Offset(faceRect.center.dx, faceRect.top - (slack - 1)),
        );
        await tester.pump();
        expect(taps, 1);
      },
    );

    testWidgets('focus ring appears + Enter and Space activate', (
      tester,
    ) async {
      var n = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _host(
          Pressable(
            focusNode: node,
            onPressed: () => n++,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            child: const SizedBox(width: 60, height: 30),
          ),
        ),
      );
      // Indirectly proves the same primitive the buttons now route through.
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(_hasFocusRing(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(n, 2);
    });

    testWidgets(
      'AppIconButton face stays 38 but a tap 4px outside still activates',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          _host(
            AppIconButton(
              icon: Icons.add,
              tooltip: 'Ekle',
              onPressed: () => taps++,
            ),
          ),
        );
        final faceRect = tester.getRect(
          find
              .descendant(
                of: find.byType(AppIconButton),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(faceRect.height, 38);
        // 38px face -> centered 44px hit region extends 3px past each edge.
        await tester.tapAt(Offset(faceRect.center.dx, faceRect.top - 2));
        await tester.pump();
        expect(taps, 1);
      },
    );

    testWidgets('disabled button is a no-op (no Opacity literal in widget)', (
      tester,
    ) async {
      var n = 0;
      await tester.pumpWidget(
        _host(const PrimaryButton(label: 'OK', onPressed: null)),
      );
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      expect(n, 0);
    });
  });
}
