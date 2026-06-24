import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/app_text_field.dart';
import 'package:sshall/widgets/app_toggle.dart';
import 'package:sshall/widgets/buttons.dart';

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

  testWidgets('AppTextField focused border uses the focusRing token', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AppTextField(
          controller: TextEditingController(),
          label: 'Host',
          autofocus: true,
        ),
      ),
    );
    await tester.pump();
    // Find the InputDecorator's focused border color.
    final field = tester.widget<TextField>(find.byType(TextField));
    final focused = field.decoration!.focusedBorder as OutlineInputBorder;
    expect(focused.borderSide.color, AppColors.night.focusRing);
  });

  testWidgets('button + toggle draw the SAME focusRing color when focused', (
    tester,
  ) async {
    // Button.
    final bNode = FocusNode();
    addTearDown(bNode.dispose);
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(label: 'OK', onPressed: () {}),
            const SizedBox(height: 12),
            AppToggle(
              value: false,
              label: 'X',
              showLabel: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    // Tab to the first focusable (the button) -> ring in focusRing color.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_hasFocusRing(tester), isTrue);
    // Tab to the toggle -> still the same focusRing color.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_hasFocusRing(tester), isTrue);
  });

  test(
    'shared widget sources carry no raw Colors.* / Color(0x literals (D7)',
    () {
      // The interaction-bearing shared widgets must source every color from a
      // token (ADR 0040 D7): no `Colors.white`, no `Color(0x..)` literals.
      final files = [
        'lib/widgets/pressable.dart',
        'lib/widgets/buttons.dart',
        'lib/widgets/app_toggle.dart',
      ];
      final raw = RegExp(r'Colors\.(?!transparent)|Color\(0x');
      for (final path in files) {
        final src = File(path).readAsStringSync();
        // Strip line comments so doc-text mentioning a color name doesn't trip it.
        final stripped = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(
          raw.hasMatch(stripped),
          isFalse,
          reason: '$path must not use raw Colors.*/Color(0x (use tokens)',
        );
      }
    },
  );
}
