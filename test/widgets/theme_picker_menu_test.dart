import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/theme_picker_menu.dart';

Widget _frame(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'shared menu renders every theme with its canonical label, in order',
    (tester) async {
      await tester.pumpWidget(
        _frame(
          Builder(
            builder: (context) => Column(
              children: [
                for (final id in AppThemeId.values)
                  ThemePickerMenu.row(context, id, AppThemeId.night),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Exactly the canonical label set, sourced from AppThemeIdLabel — not a
      // local literal — so it can never drift from Settings.
      for (final id in AppThemeId.values) {
        expect(find.text(id.label), findsOneWidget);
      }
      // The active theme is marked once.
      expect(find.byIcon(Icons.check), findsOneWidget);
      // A colour swatch per theme.
      for (final id in AppThemeId.values) {
        expect(find.byKey(Key('themeSwatch_${id.name}')), findsOneWidget);
      }
    },
  );

  testWidgets('items() yields one PopupMenuItem per theme in canonical order', (
    tester,
  ) async {
    late List<PopupMenuEntry<AppThemeId>> built;
    await tester.pumpWidget(
      _frame(
        Builder(
          builder: (context) {
            built = ThemePickerMenu.items(context, AppThemeId.day);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      built.whereType<PopupMenuItem<AppThemeId>>().length,
      AppThemeId.values.length,
    );
    final values = built
        .whereType<PopupMenuItem<AppThemeId>>()
        .map((e) => e.value)
        .toList();
    expect(values, AppThemeId.values);
  });
}
