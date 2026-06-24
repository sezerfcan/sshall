import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/folders/connection_ops.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/resolve/connection_resolver.dart';
import 'package:sshall/features/connect/edit_connection_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

Connection _conn() => const Connection(
  id: 'c1',
  label: 'web',
  host: '10.0.0.1',
  folderId: null,
  username: 'root',
  port: 2222,
  authRef: 'i1',
  tags: ['prod'],
  order: 0,
);

Identity _identity() => const Identity(
  id: 'i1',
  label: 'web',
  type: IdentityType.password,
  secret: 'pw',
  passphrase: null,
);

Future<EditConnectionResult?> _open(
  WidgetTester tester, {
  Connection? conn,
  Identity? id,
}) async {
  final c = conn ?? _conn();
  EditConnectionResult? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showEditConnectionDialog(
                context,
                connection: c,
                identity: id ?? _identity(),
                resolved: resolve(c, const []),
                folders: const [],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('prefills label/host and concrete user/port', (tester) async {
    await _open(tester);
    expect(
      find.widgetWithText(TextField, 'web'),
      findsWidgets,
    ); // label prefilled
    expect(find.text('10.0.0.1'), findsOneWidget); // host
    expect(find.text('2222'), findsOneWidget); // port
  });

  testWidgets('empty password keeps existing identity', (tester) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.delete, isFalse);
    expect(result!.identity, isA<IdentityKeep>());
    expect(result!.username, isA<SetValue<String>>());
    expect((result!.username as SetValue<String>).value, 'root');
  });

  testWidgets('typing a new password yields IdentitySetPassword', (
    tester,
  ) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-password')), 'newpw');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result!.identity, isA<IdentitySetPassword>());
    expect((result!.identity as IdentitySetPassword).password, 'newpw');
  });

  testWidgets('inherit toggle for username produces Inherit', (tester) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-user-inherit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result!.username, isA<Inherit<String>>());
  });

  testWidgets('empty label blocks save with an error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-label')), '');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Etiket boş olamaz.'), findsOneWidget);
  });

  testWidgets('delete button confirms then returns remove()', (tester) async {
    final result = await () async {
      EditConnectionResult? r;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final c = _conn();
                  r = await showEditConnectionDialog(
                    context,
                    connection: c,
                    identity: _identity(),
                    resolved: resolve(c, const []),
                    folders: const [],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evet, sil'));
      await tester.pumpAndSettle();
      return r;
    }();
    expect(result!.delete, isTrue);
  });

  testWidgets('inherit toggle for identity produces IdentityInherit', (
    tester,
  ) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The identity inherit toggle sits below the fold of the scrollable
    // dialog body; bring it into view so the tap actually hits it.
    await tester.ensureVisible(find.byKey(const Key('edit-id-inherit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-id-inherit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.delete, isFalse);
    expect(result!.identity, isA<IdentityInherit>());
  });

  testWidgets('inherit→concrete with empty secret blocks save with an error', (
    tester,
  ) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                const c = Connection(
                  id: 'c1',
                  label: 'web',
                  host: '10.0.0.1',
                  folderId: null,
                  username: 'root',
                  port: 2222,
                  authRef: null,
                  tags: ['prod'],
                  order: 0,
                );
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: null,
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Toggle identity OFF (concrete) — scroll it into view first so the tap
    // lands on it rather than an off-screen position.
    await tester.ensureVisible(find.byKey(const Key('edit-id-inherit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-id-inherit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Parola girin.'), findsOneWidget);
    expect(result, isNull);
  });

  // Type-switch guard: existing identity is a PASSWORD; user flips to key mode
  // but picks no key — save must be blocked, never silently kept as the old
  // password identity.
  testWidgets('switch password->key with no key picked blocks save', (
    tester,
  ) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: _identity(),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('edit-useKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-useKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Bir özel anahtar seçin.'), findsOneWidget);
    expect(result, isNull);
  });

  // Mirror guard: existing identity is a KEY; user flips to password mode but
  // leaves the password empty — save must be blocked, not kept as the old key.
  testWidgets('switch key->password with empty password blocks save', (
    tester,
  ) async {
    EditConnectionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final c = _conn();
                result = await showEditConnectionDialog(
                  context,
                  connection: c,
                  identity: const Identity(
                    id: 'i1',
                    label: 'web',
                    type: IdentityType.privateKey,
                    secret: 'PEM',
                    passphrase: null,
                  ),
                  resolved: resolve(c, const []),
                  folders: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('edit-useKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-useKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Parola girin.'), findsOneWidget);
    expect(result, isNull);
  });
}
