import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/chmod_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  testWidgets('toggling a bit and confirming returns the new mode',
      (tester) async {
    int? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showChmodDialog(ctx,
                  name: 'run.sh', mode: 0x1A4), // 0644
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // The octal preview starts at 644.
    expect(find.text('644'), findsOneWidget);
    // Toggle "owner execute" -> 744.
    await tester.tap(find.byKey(const ValueKey('perm_user_x')));
    await tester.pumpAndSettle();
    expect(find.text('744'), findsOneWidget);
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(result, 0x1E4); // 0744
  });
}
