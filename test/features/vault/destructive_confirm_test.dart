import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/vault/confirm_dialog.dart';
import 'package:sshall/widgets/buttons.dart';
import 'package:sshall/theme/app_colors.dart';

Future<bool?> _open(WidgetTester tester) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showDestructiveConfirm(
                  context,
                  title: 'Tehlikeli işlem',
                  confirmLabel: 'Sil',
                  confirmKey: const Key('danger'),
                  bodyBuilder: (ctx) => const Text('3 bağlantı etkilenecek'),
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('confirm button is danger-styled (DangerButton)', (tester) async {
    await _open(tester);
    expect(find.byType(DangerButton), findsOneWidget);
  });

  testWidgets('body states the concrete blast radius', (tester) async {
    await _open(tester);
    expect(find.text('3 bağlantı etkilenecek'), findsOneWidget);
  });

  testWidgets('Enter does NOT confirm (explicit click required — D7)', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDestructiveConfirm(
                    context,
                    title: 'T',
                    confirmLabel: 'Sil',
                    bodyBuilder: (ctx) => const Text('body'),
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Press Enter — must NOT confirm; the dialog stays open.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, isNull); // still open, not confirmed
    expect(find.text('body'), findsOneWidget);

    // An explicit click confirms.
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDestructiveConfirm(
                    context,
                    title: 'T',
                    confirmLabel: 'Sil',
                    bodyBuilder: (ctx) => const Text('body'),
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
