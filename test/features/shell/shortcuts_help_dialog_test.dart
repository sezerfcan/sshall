import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shortcuts_help_dialog.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appThemeData(AppThemeId.night),
      home: const Scaffold(body: ShortcutsHelpDialog()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the help dialog title', (tester) async {
    await _pump(tester);
    expect(
      find.text('Klavye Kısayolları & Sekme Etkileşimleri'),
      findsOneWidget,
    );
  });

  testWidgets('shows the Docker section heading and at least one row', (
    tester,
  ) async {
    await _pump(tester);
    // Section headings are upper-cased by _section.
    expect(find.text('DOCKER'), findsOneWidget);
    // The "Terminal aç" row describes the docker exec interactive shell.
    expect(find.text('Terminal aç'), findsOneWidget);
  });

  testWidgets('lists the new tab / merge shortcuts and rename interaction '
      '(ADR 0036 D9)', (tester) async {
    await _pump(tester);
    // New keyboard shortcuts.
    expect(find.text('⌘T'), findsOneWidget);
    expect(find.text('⌘⇧\\'), findsOneWidget);
    // Rename is discoverable as a mouse interaction.
    expect(find.text('Çift tık (başlık)'), findsOneWidget);
  });
}
