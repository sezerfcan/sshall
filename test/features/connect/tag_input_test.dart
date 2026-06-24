import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/connect/widgets/tag_input.dart';
import 'package:sshall/theme/app_colors.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.night]),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('Enter commits a chip', (tester) async {
    final controller = TagInputController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(TagInput(controller: controller)));

    await tester.enterText(find.byKey(const Key('tagInput')), 'prod');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.committed, ['prod']);
    expect(find.text('prod'), findsOneWidget);
  });

  testWidgets('comma commits a chip and keeps the remainder pending', (
    tester,
  ) async {
    final controller = TagInputController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(TagInput(controller: controller)));

    await tester.enterText(find.byKey(const Key('tagInput')), 'prod,db');
    await tester.pump();

    expect(controller.committed, ['prod']);
    expect(controller.text.text, 'db');
  });

  testWidgets('× removes a chip', (tester) async {
    final controller = TagInputController(initial: ['prod', 'db']);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(TagInput(controller: controller)));

    await tester.tap(find.byKey(const Key('removeTag-prod')));
    await tester.pump();
    expect(controller.committed, ['db']);
  });

  testWidgets('pending (uncommitted) input is NOT lost on read', (
    tester,
  ) async {
    final controller = TagInputController(initial: ['prod']);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(TagInput(controller: controller)));

    await tester.enterText(find.byKey(const Key('tagInput')), 'db');
    await tester.pump();

    // committed has only the explicit chip, but tags folds in the pending text.
    expect(controller.committed, ['prod']);
    expect(controller.tags, ['prod', 'db']);
  });

  testWidgets('duplicate tags are ignored', (tester) async {
    final controller = TagInputController(initial: ['prod']);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(TagInput(controller: controller)));

    await tester.enterText(find.byKey(const Key('tagInput')), 'prod');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.committed, ['prod']);
  });
}
