import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/features/connect/connect_dialog.dart';
import 'package:sshall/theme/app_colors.dart' show AppThemeId;
import 'package:sshall/theme/app_theme.dart';

/// Golden coverage for the rebuilt "Add Host" dialog (ADR 0031) across all three
/// themes (night / day / terminal). Captures the default key-auth mode, plus a
/// password-mode and an advanced-expanded variant. Regenerate with:
///   flutter test --update-goldens test/features/connect/goldens/connect_dialog_golden_test.dart
/// then run WITHOUT the flag to confirm they pass.

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

Future<void> _open(WidgetTester tester, AppThemeId theme) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appThemeData(theme),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showConnectDialog(
                  context,
                  folders: _folders,
                  identities: _identities,
                ),
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in AppThemeId.values) {
    testWidgets('connect dialog golden — ${theme.name} (key auth)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(620, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _open(tester, theme);
      // Switch to key-auth mode (default is password).
      await tester.tap(find.byKey(const Key('authSegKey')));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AlertDialog),
        matchesGoldenFile('connect_dialog_${theme.name}_key.png'),
      );
    });
  }

  testWidgets('connect dialog golden — night (password)', (tester) async {
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _open(tester, AppThemeId.night);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('connect_dialog_night_password.png'),
    );
  });

  testWidgets('connect dialog golden — night (advanced expanded)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 880);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _open(tester, AppThemeId.night);
    await tester.ensureVisible(find.byKey(const Key('advancedToggle')));
    await tester.tap(find.byKey(const Key('advancedToggle')));
    await tester.pumpAndSettle();
    // The Docker toggle sits at the bottom of the scrollable content and is
    // off-screen once the advanced section expands; scroll it into view so the
    // tap hits the real on-screen control instead of warning on a missed
    // hit-test.
    await tester.ensureVisible(find.byKey(const Key('dockerFlag')));
    await tester.tap(find.byKey(const Key('dockerFlag')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('connect_dialog_night_advanced.png'),
    );
  });
}
