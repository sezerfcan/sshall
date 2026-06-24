import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/app_toggle.dart';

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
  setUp(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional,
  );
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  testWidgets('tapping the visible label toggles (label is part of control)', (
    tester,
  ) async {
    bool? got;
    await tester.pumpWidget(
      _host(
        AppToggle(
          value: false,
          label: 'Özel anahtar kullan',
          showLabel: true,
          onChanged: (v) => got = v,
        ),
      ),
    );
    // The label is rendered as visible text, exactly once.
    expect(find.text('Özel anahtar kullan'), findsOneWidget);
    // Tapping the label (not the track) toggles.
    await tester.tap(find.text('Özel anahtar kullan'));
    expect(got, isTrue);
  });

  testWidgets('Enter and Space toggle the control', (tester) async {
    var flips = 0;
    await tester.pumpWidget(
      _host(
        AppToggle(
          value: false,
          label: 'Yeni kimlik',
          showLabel: true,
          onChanged: (_) => flips++,
        ),
      ),
    );
    // Tab into the toggle's own focusable (the shared Pressable primitive).
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_hasFocusRing(tester), isTrue, reason: 'toggle should be focused');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(flips, 2);
  });

  testWidgets('row is a >=44px tall hit target (track stays 23) + focus ring', (
    tester,
  ) async {
    var flips = 0;
    await tester.pumpWidget(
      _host(AppToggle(value: false, onChanged: (_) => flips++)),
    );
    // The painted track is 23 tall and the AppToggle does not inflate layout.
    final rect = tester.getRect(find.byType(AppToggle));
    expect(rect.height, 23);
    // A tap 8px above the 23px track — inside the centered 44px hit region —
    // still toggles, proving the effective target is >=44 tall.
    await tester.tapAt(Offset(rect.center.dx, rect.top - 8));
    await tester.pump();
    expect(flips, 1);
    // Keyboard focus shows the shared focus ring.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_hasFocusRing(tester), isTrue);
  });

  testWidgets('knob uses the onAccent token (no raw Colors.white)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AppToggle(value: true, onChanged: (_) {})));
    // Find the round knob Container and assert its color is the token.
    final knob = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere((con) {
          final d = con.decoration;
          return d is BoxDecoration && d.shape == BoxShape.circle;
        });
    final dec = knob.decoration as BoxDecoration;
    expect(dec.color, AppColors.night.onAccent);
  });

  testWidgets('label==null renders only the track (backward compatible)', (
    tester,
  ) async {
    bool? got;
    await tester.pumpWidget(
      _host(AppToggle(value: false, onChanged: (v) => got = v)),
    );
    expect(find.byType(Text), findsNothing);
    await tester.tap(find.byType(AppToggle));
    expect(got, isTrue);
  });
}
