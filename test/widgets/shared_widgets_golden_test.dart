import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/app_toggle.dart';
import 'package:sshall/widgets/buttons.dart';

/// Golden coverage for ONLY the surfaces ADR 0040 pass-1 legitimately changes:
///  1. the AppToggle-label rows (the toggle now renders its OWN tappable label
///     in place of the old untappable sibling `Text`), and
///  2. a focus-state scene (a keyboard-focused button + toggle showing the new
///     additive focus ring).
///
/// At-rest button/dialog/feature goldens are intentionally NOT covered here —
/// pass-1 keeps them byte-identical. Regenerate with:
///   flutter test --update-goldens test/widgets/shared_widgets_golden_test.dart
Widget _frame(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('AppToggle-label rows (own label, no sibling Text) — night', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _frame(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppToggle(
              value: true,
              label: 'Klasörden miras al',
              showLabel: true,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            AppToggle(
              value: false,
              label: 'Özel anahtar kullan',
              showLabel: true,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            AppToggle(
              value: false,
              label: 'Yeni kimlik',
              showLabel: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Column),
      matchesGoldenFile('goldens/toggle_label_rows_night.png'),
    );
  });

  testWidgets('focus-state — keyboard-focused button shows the focus ring', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    tester.view.physicalSize = const Size(360, 160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _frame(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PrimaryButton(label: 'Bağlan', onPressed: () {}),
            const SizedBox(height: 16),
            AppToggle(
              value: true,
              label: 'Onay iste',
              showLabel: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    // Tab to focus the button so its ring is rendered.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Column),
      matchesGoldenFile('goldens/focus_state_button_night.png'),
    );
  });
}
