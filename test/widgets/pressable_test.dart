import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/pressable.dart';

Widget _host(Widget child) => MaterialApp(
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(body: Center(child: child)),
);

/// Collect all overlay/border colors rendered by the Pressable's internal
/// AnimatedContainer + DecoratedBox so a test can assert the state wash + ring.
Iterable<Color?> _decorationColors(WidgetTester tester) sync* {
  for (final w in tester.widgetList(find.byType(AnimatedContainer))) {
    final d = (w as AnimatedContainer).decoration;
    if (d is BoxDecoration) yield d.color;
  }
}

bool _hasFocusRing(WidgetTester tester) {
  for (final w in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final d = w.decoration;
    if (d is BoxDecoration && d.border != null) {
      final side = (d.border as Border).top;
      if (side.color == AppColors.night.focusRing) return true;
    }
  }
  return false;
}

void main() {
  setUp(() {
    // Force the keyboard focus-ring behavior so requestFocus() shows the ring
    // (the default strategy can suppress the highlight in a headless test).
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('hover wash appears on pointer enter', (tester) async {
    await tester.pumpWidget(
      _host(
        Pressable(
          onPressed: () {},
          child: const SizedBox(width: 80, height: 30),
        ),
      ),
    );
    expect(
      _decorationColors(tester).contains(AppColors.night.hoverOverlay),
      isFalse,
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Pressable)));
    await tester.pumpAndSettle();

    expect(
      _decorationColors(tester).contains(AppColors.night.hoverOverlay),
      isTrue,
    );
  });

  testWidgets('pressed wash appears on tap down (stronger than hover)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Pressable(
          onPressed: () {},
          child: const SizedBox(width: 80, height: 30),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    expect(
      _decorationColors(tester).contains(AppColors.night.pressedOverlay),
      isTrue,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('no ring at rest; keyboard focus shows the ring', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _host(
        Pressable(
          focusNode: node,
          onPressed: () {},
          child: const SizedBox(width: 80, height: 30),
        ),
      ),
    );
    expect(_hasFocusRing(tester), isFalse);

    // Keyboard focus (FocusableActionDetector reports it as a focus highlight).
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(_hasFocusRing(tester), isTrue);
  });

  testWidgets('Enter AND Space both activate', (tester) async {
    var enter = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _host(
        Pressable(
          focusNode: node,
          onPressed: () => enter++,
          child: const SizedBox(width: 80, height: 30),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(enter, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(enter, 2);
  });

  testWidgets('focus is additive over selected (both selectedBg + ring)', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _host(
        Pressable(
          focusNode: node,
          selected: true,
          onPressed: () {},
          child: const SizedBox(width: 80, height: 30),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    // selectedBg wash present AND the ring present at the same time.
    expect(
      _decorationColors(tester).contains(AppColors.night.selectedBg),
      isTrue,
    );
    expect(_hasFocusRing(tester), isTrue);
  });

  testWidgets('disabled swallows tap/Enter/Space and shows no states', (
    tester,
  ) async {
    var taps = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _host(
        Pressable(
          focusNode: node,
          onPressed: null, // disabled
          child: const SizedBox(width: 80, height: 30),
        ),
      ),
    );
    await tester.tap(find.byType(Pressable), warnIfMissed: false);
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 0);
    expect(_hasFocusRing(tester), isFalse);
  });

  testWidgets(
    'hit target is >=44px (a tap above the painted child still activates) '
    'while the painted child stays small and layout is unchanged',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Pressable(
            onPressed: () => taps++,
            child: const SizedBox(key: Key('paint'), width: 80, height: 24),
          ),
        ),
      );
      // Painted child unchanged (24px tall), and the Pressable does NOT inflate
      // its layout box (still the child height — no pushing of siblings).
      expect(tester.getSize(find.byKey(const Key('paint'))).height, 24);
      expect(tester.getSize(find.byType(Pressable)).height, 24);

      // A tap 8px ABOVE the painted child's top edge — outside the 24px paint but
      // inside the centered 44px hit region — must still activate.
      final rect = tester.getRect(find.byKey(const Key('paint')));
      await tester.tapAt(Offset(rect.center.dx, rect.top - 8));
      await tester.pump();
      expect(taps, 1);
    },
  );
}
