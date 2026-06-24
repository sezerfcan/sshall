import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/features/connect/connect_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.night]),
  home: child,
);

const _folders = [
  Folder(
    id: 'work',
    parentId: null,
    name: 'work',
    username: null,
    port: null,
    authRef: null,
    order: 0,
  ),
];

const _identities = [
  Identity(
    id: 'i1',
    label: 'shared-key',
    type: IdentityType.privateKey,
    secret: 'PEM',
    passphrase: null,
  ),
];

/// A dialog test harness: pumps a host with an "open" button, opens the dialog,
/// and exposes the captured result via [result] (read AFTER the dialog closes).
class _Harness {
  final WidgetTester tester;
  ConnectDialogResult? result;
  _Harness(this.tester);

  Future<void> open({
    ConnectPrefill? prefill,
    List<Folder> folders = const [],
    List<Identity> identities = const [],
    String? defaultUsername,
    int? defaultPort,
  }) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                result = await showConnectDialog(
                  context,
                  prefill: prefill,
                  folders: folders,
                  identities: identities,
                  defaultUsername: defaultUsername,
                  defaultPort: defaultPort,
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }
}

String _fieldText(WidgetTester tester, Key k) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(k), matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
  testWidgets('a: no "Vault\'a kaydet" toggle; fields are unconditional (D1)', (
    tester,
  ) async {
    await _Harness(tester).open();
    expect(find.text("Vault'a kaydet"), findsNothing);
    // Saved-host metadata fields are always visible.
    expect(find.byKey(const Key('label')), findsOneWidget);
    expect(find.byKey(const Key('folder')), findsOneWidget);
    expect(find.byKey(const Key('tagInput')), findsOneWidget);
  });

  testWidgets(
    'b: Label auto-derives from Host until the user edits Label (D2)',
    (tester) async {
      await _Harness(tester).open();

      await tester.enterText(find.byKey(const Key('host')), 'example.com');
      await tester.pump();
      final label = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('label')),
          matching: find.byType(EditableText),
        ),
      );
      expect(label.controller.text, 'example.com');

      // Edit the label manually, then change host: derive must stop.
      await tester.enterText(find.byKey(const Key('label')), 'My Box');
      await tester.enterText(find.byKey(const Key('host')), 'other.com');
      await tester.pump();
      final label2 = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('label')),
          matching: find.byType(EditableText),
        ),
      );
      expect(label2.controller.text, 'My Box');
    },
  );

  testWidgets('c: Host + Port are on the same Row (D2)', (tester) async {
    await _Harness(tester).open();
    final row = find.ancestor(
      of: find.byKey(const Key('host')),
      matching: find.byType(Row),
    );
    // The nearest Row enclosing Host also encloses Port.
    expect(
      find.descendant(of: row.first, matching: find.byKey(const Key('port'))),
      findsOneWidget,
    );
  });

  testWidgets('d: empty Host/Label submit → field errors, focus first invalid, '
      'clears live, no aggregate error (D5)', (tester) async {
    await _Harness(tester).open();

    // Clear the auto-derived label so both label and host are empty.
    await tester.enterText(find.byKey(const Key('label')), '');
    await tester.tap(find.byKey(const Key('saveAndConnect')));
    await tester.pumpAndSettle();

    expect(find.text('Etiket boş olamaz.'), findsOneWidget);
    expect(find.text('Host boş olamaz.'), findsOneWidget);
    // Dialog stays open.
    expect(find.text('Yeni Bağlantı'), findsOneWidget);

    // Fix the label; its error clears live.
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.pump();
    expect(find.text('Etiket boş olamaz.'), findsNothing);
  });

  testWidgets('e: Advanced disclosure expands/collapses (D2)', (tester) async {
    await _Harness(tester).open();
    expect(find.byKey(const Key('dockerFlag')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('advancedToggle')));
    await tester.tap(find.byKey(const Key('advancedToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dockerFlag')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('advancedToggle')));
    await tester.tap(find.byKey(const Key('advancedToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dockerFlag')), findsNothing);
  });

  testWidgets('f: Escape cancels (D7)', (tester) async {
    await _Harness(tester).open();
    expect(find.text('Yeni Bağlantı'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Yeni Bağlantı'), findsNothing);
  });

  testWidgets('g: pasting user@host:port into Host splits the fields (D7)', (
    tester,
  ) async {
    await _Harness(tester).open();
    await tester.enterText(
      find.byKey(const Key('host')),
      'root@example.com:2222',
    );
    await tester.pump();

    String text(Key k) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(k),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;
    expect(text(const Key('host')), 'example.com');
    expect(text(const Key('username')), 'root');
    expect(text(const Key('port')), '2222');
  });

  testWidgets('h: "Kaydet" → action save (D4)', (tester) async {
    final h = _Harness(tester);
    await h.open(folders: _folders);
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.enterText(find.byKey(const Key('host')), 'example.com');
    await tester.enterText(find.byKey(const Key('username')), 'root');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.tap(find.byKey(const Key('saveOnly')));
    await tester.pumpAndSettle();
    expect(h.result, isNotNull);
    expect(h.result!.action, ConnectAction.save);
    expect(h.result!.params.host, 'example.com');
    expect(h.result!.params.username, 'root');
    expect(h.result!.params.password, 'pw');
    expect(h.result!.label, 'Box');
  });

  testWidgets('saveAndConnect returns the connect action', (tester) async {
    final h = _Harness(tester);
    await h.open();
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.enterText(find.byKey(const Key('host')), 'example.com');
    await tester.enterText(find.byKey(const Key('username')), 'root');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.tap(find.byKey(const Key('saveAndConnect')));
    await tester.pumpAndSettle();
    expect(h.result, isNotNull);
    expect(h.result!.action, ConnectAction.saveAndConnect);
    expect(h.result!.connect, isTrue);
  });

  testWidgets('Enter submits the PRIMARY action (saveAndConnect) (D7)', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.open();
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.enterText(find.byKey(const Key('host')), 'example.com');
    await tester.enterText(find.byKey(const Key('username')), 'root');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(h.result, isNotNull);
    expect(h.result!.action, ConnectAction.saveAndConnect);
  });

  testWidgets('reusing an existing identity sets existingAuthRef and ships no '
      'secret (D8)', (tester) async {
    final h = _Harness(tester);
    await h.open(identities: _identities);
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.enterText(find.byKey(const Key('host')), 'example.com');
    await tester.enterText(find.byKey(const Key('username')), 'root');

    // Switch to key mode and pick the existing identity.
    await tester.tap(find.byKey(const Key('authSegKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('authIdentity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shared-key').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saveOnly')));
    await tester.pumpAndSettle();

    expect(h.result, isNotNull);
    expect(h.result!.existingAuthRef, 'i1');
    expect(h.result!.params.password, isNull);
    expect(h.result!.params.privateKeyPem, isNull); // resolved from identity
  });

  testWidgets('saved folder + tags are carried on the result (D6)', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.open(folders: _folders);
    await tester.enterText(find.byKey(const Key('label')), 'Box');
    await tester.enterText(find.byKey(const Key('host')), 'example.com');
    await tester.enterText(find.byKey(const Key('username')), 'root');
    await tester.enterText(find.byKey(const Key('password')), 'pw');

    await tester.ensureVisible(find.byKey(const Key('folder')));
    await tester.tap(find.byKey(const Key('folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('work').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tagInput')), 'prod');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('tagInput')), 'db');
    await tester.pump();

    await tester.tap(find.byKey(const Key('saveOnly')));
    await tester.pumpAndSettle();

    expect(h.result, isNotNull);
    expect(h.result!.folderId, 'work');
    // Committed 'prod' + pending 'db' both make it through (no half-tag lost).
    expect(h.result!.tags, ['prod', 'db']);
  });

  // --- connection defaults from settings (ADR 0038 D6) ---------------------

  testWidgets('backward compatible: no settings → port still defaults to 22', (
    tester,
  ) async {
    await _Harness(tester).open();
    expect(_fieldText(tester, const Key('port')), '22');
  });

  testWidgets('settings default port feeds the dialog (port 2222)', (
    tester,
  ) async {
    await _Harness(tester).open(defaultPort: 2222);
    expect(_fieldText(tester, const Key('port')), '2222');
  });

  testWidgets('settings default username pre-fills the username field', (
    tester,
  ) async {
    await _Harness(tester).open(defaultUsername: 'deploy');
    expect(_fieldText(tester, const Key('username')), 'deploy');
  });

  testWidgets('prefill (Quick Connect) wins over the settings default', (
    tester,
  ) async {
    await _Harness(tester).open(
      prefill: const ConnectPrefill(port: 8022, username: 'admin'),
      defaultPort: 2222,
      defaultUsername: 'deploy',
    );
    expect(_fieldText(tester, const Key('port')), '8022');
    expect(_fieldText(tester, const Key('username')), 'admin');
  });

  testWidgets('Turkish labels, no leftover English', (tester) async {
    await _Harness(tester).open();
    expect(find.text('Etiket'), findsOneWidget);
    expect(find.text('Kullanıcı adı'), findsOneWidget);
    expect(find.text('SSH Anahtarı'), findsOneWidget);
    expect(find.text('Bağlan ve kaydet'), findsOneWidget);
    expect(find.text('Kaydet'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
    expect(find.text('Save to vault'), findsNothing);
  });
}
