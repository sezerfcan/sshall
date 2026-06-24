import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/vault/reset_vault_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

Widget _host(void Function(bool) onResult) => MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async => onResult(await showResetVaultDialog(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('confirm is gated on typing SIFIRLA and returns true',
      (tester) async {
    bool? result;
    await tester.pumpWidget(_host((r) => result = r));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    // Tapping confirm with no phrase does nothing — dialog stays open.
    await tester.tap(find.byKey(const Key('confirmReset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resetConfirmPhrase')), findsOneWidget);
    expect(result, isNull);

    // Wrong text keeps it gated.
    await tester.enterText(find.byKey(const Key('resetConfirmPhrase')), 'nope');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmReset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resetConfirmPhrase')), findsOneWidget);
    expect(result, isNull);

    // Correct phrase (case-insensitive) enables confirm → returns true & closes.
    await tester.enterText(
        find.byKey(const Key('resetConfirmPhrase')), 'sifirla');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmReset')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byKey(const Key('resetConfirmPhrase')), findsNothing);
  });

  testWidgets('cancel returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(_host((r) => result = r));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
