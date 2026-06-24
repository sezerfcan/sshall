import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/features/unlock/unlock_screen.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  testWidgets('shows Create vault when no vault exists', (tester) async {
    // IO operations must escape fakeAsync via runAsync.
    final tmp =
        await tester.runAsync(() => Directory.systemTemp.createTemp('sshall_unlock'));
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Pre-resolve the FutureProvider chain in real async before building the
    // widget so the screen renders its data state immediately on first pump.
    final container = ProviderContainer(overrides: [
      keyringProvider.overrideWithValue(InMemoryKeyring()),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appThemeData(AppThemeId.night),
        home: UnlockScreen(onUnlocked: () {}),
      ),
    ));
    // One pump resolves the FutureBuilder (store.vaultExists() real IO).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    // Field found by Key('passphrase'); button label is 'Oluştur' in create mode.
    expect(find.byKey(const Key('passphrase')), findsOneWidget);
    expect(find.text('Oluştur'), findsOneWidget);
    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
