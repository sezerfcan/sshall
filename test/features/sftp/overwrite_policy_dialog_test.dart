import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/overwrite_policy_dialog.dart';
import 'package:sshall/services/sftp/transfer_plan.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  testWidgets('returns the chosen policy', (tester) async {
    OverwritePolicy? chosen;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async =>
                chosen = await showOverwritePolicyDialog(ctx, 'docs'),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Folder name is shown and all three policies are offered.
    expect(find.textContaining('docs'), findsOneWidget);
    expect(find.text('Mevcutları atla'), findsOneWidget);
    expect(find.text('Her birini sor'), findsOneWidget);

    await tester.tap(find.text('Mevcutları atla'));
    await tester.pumpAndSettle();
    expect(chosen, OverwritePolicy.skipExisting);
  });
}
