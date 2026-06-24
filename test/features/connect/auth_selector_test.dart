import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/features/connect/widgets/auth_selector.dart';
import 'package:sshall/theme/app_colors.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.night]),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'retains password text across a segment switch (D3 state-loss fix)',
    (tester) async {
      final controller = AuthSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(AuthSelector(controller: controller)));

      // Type a password in the default (password) segment.
      await tester.enterText(find.byKey(const Key('password')), 'secret');
      await tester.pump();

      // Switch to SSH key, then back to password.
      await tester.tap(find.byKey(const Key('authSegKey')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('authSegPassword')));
      await tester.pump();

      // The text survived the round-trip (the old boolean toggle cleared it).
      expect(controller.password.text, 'secret');
      expect(find.text('secret'), findsOneWidget);
    },
  );

  testWidgets('reveal toggle shows/hides the password', (tester) async {
    final controller = AuthSelectionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(AuthSelector(controller: controller)));

    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.pump();

    // Obscured initially: the fieldKey is on the inner TextField itself.
    TextField field() =>
        tester.widget<TextField>(find.byKey(const Key('password')));
    expect(field().obscureText, isTrue);

    await tester.tap(find.byKey(const Key('revealToggle')).first);
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('selecting an existing identity sets the ref (key mode)', (
    tester,
  ) async {
    final controller = AuthSelectionController();
    addTearDown(controller.dispose);
    const identities = [
      Identity(
        id: 'i1',
        label: 'shared-key',
        type: IdentityType.privateKey,
        secret: 'PEM',
        passphrase: null,
      ),
    ];

    await tester.pumpWidget(
      _wrap(AuthSelector(controller: controller, identities: identities)),
    );

    await tester.tap(find.byKey(const Key('authSegKey')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('authIdentity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shared-key').last);
    await tester.pumpAndSettle();

    expect(controller.selectedIdentityId, 'i1');
    expect(controller.hasExistingIdentity, isTrue);
  });

  testWidgets('segments and import button carry tooltips/labels (§9)', (
    tester,
  ) async {
    final controller = AuthSelectionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(AuthSelector(controller: controller)));

    expect(find.text('SSH Anahtarı'), findsOneWidget);
    expect(find.text('Parola'), findsWidgets);

    await tester.tap(find.byKey(const Key('authSegKey')));
    await tester.pump();
    expect(find.byKey(const Key('importKey')), findsOneWidget);
    expect(find.byKey(const Key('authIdentity')), findsOneWidget);
  });

  testWidgets('credentialError is shown when provided', (tester) async {
    final controller = AuthSelectionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wrap(
        AuthSelector(
          controller: controller,
          credentialError: 'Parola boş olamaz.',
        ),
      ),
    );
    expect(find.text('Parola boş olamaz.'), findsOneWidget);
  });
}
