import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/overwrite_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  test('uniqueName inserts a counter before the extension', () {
    final taken = {'a.txt', 'a (1).txt'};
    expect(uniqueName('a.txt', taken.contains), 'a (2).txt');
    expect(uniqueName('b.txt', taken.contains), 'b.txt');
    expect(uniqueName('noext', taken.contains), 'noext');
  });

  testWidgets('dialog returns the chosen action', (tester) async {
    OverwriteChoice? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  result = await showOverwriteDialog(ctx, 'a.txt'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Üzerine yaz'));
    await tester.pumpAndSettle();
    expect(result, OverwriteChoice.overwrite);
  });
}
