import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/widgets/app_text_field.dart';
import 'package:sshall/widgets/app_toggle.dart';

Widget _host(Widget child) => MaterialApp(
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AppTextField', () {
    testWidgets('shows hintText inside the field', (tester) async {
      await tester.pumpWidget(
        _host(
          AppTextField(
            controller: TextEditingController(),
            label: 'Host',
            hintText: 'örn. 192.168.1.10',
          ),
        ),
      );
      expect(find.text('örn. 192.168.1.10'), findsOneWidget);
    });

    testWidgets('shows errorText below the field when set', (tester) async {
      await tester.pumpWidget(
        _host(
          AppTextField(
            controller: TextEditingController(),
            label: 'Host',
            errorText: 'Host boş olamaz',
          ),
        ),
      );
      expect(find.text('Host boş olamaz'), findsOneWidget);
    });

    testWidgets('does not render an error row when errorText is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AppTextField(controller: TextEditingController(), label: 'Host')),
      );
      expect(find.text('Host boş olamaz'), findsNothing);
    });

    testWidgets('exposes the label to the accessibility tree', (tester) async {
      await tester.pumpWidget(
        _host(
          AppTextField(
            controller: TextEditingController(),
            label: 'Kullanıcı adı',
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      // The label must be reachable by a screen reader. Read the merged
      // semantics node of the field wrapper and assert its label carries the
      // field name (so the field is no longer a mute input box).
      final node = tester.getSemantics(find.byType(AppTextField));
      expect(node.label, contains('Kullanıcı adı'));
      handle.dispose();
    });
  });

  group('AppToggle', () {
    testWidgets('reports flips (regression)', (tester) async {
      bool? got;
      await tester.pumpWidget(
        _host(AppToggle(value: false, onChanged: (v) => got = v)),
      );
      await tester.tap(find.byType(AppToggle));
      expect(got, isTrue);
    });

    testWidgets('exposes toggled state to the accessibility tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          AppToggle(value: true, label: 'Vault\'a kaydet', onChanged: (_) {}),
        ),
      );
      // A screen reader must be able to read on/off + label. The control is now
      // a keyboard-operable switch (ADR 0040 D5/D6): it keeps label + toggled +
      // tap and additionally is focusable/enabled. Query by the semantics label
      // so we land on the control's own node regardless of wrapper render
      // objects.
      final node = tester.getSemantics(
        find.bySemanticsLabel('Vault\'a kaydet'),
      );
      expect(node.label, contains('Vault\'a kaydet'));
      expect(
        node,
        matchesSemantics(
          label: 'Vault\'a kaydet',
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('off state is not toggled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          AppToggle(
            value: false,
            label: 'Özel anahtar kullan',
            onChanged: (_) {},
          ),
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('Özel anahtar kullan'),
      );
      expect(
        node,
        matchesSemantics(
          label: 'Özel anahtar kullan',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });
  });
}
