import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/app_shell.dart';
import 'package:sshall/features/shell/shell_metrics.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  // SftpView (IndexedStack child 2) calls this on bootstrap; IndexedStack
  // builds all children, so the fake must answer it even when SFTP isn't shown.
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Build an unlocked SecureStore backed by a real temp VaultFile + InMemoryKeyring.
Future<SecureStore> _unlockedStore(Directory dir) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  return store;
}

void main() {
  testWidgets('tapping Vault nav item opens the Vault overlay; Esc closes it', (
    tester,
  ) async {
    // Runs at the default 800px test viewport: VaultView's stat row is now
    // responsive (see _StatRow / vault_view_test.dart), so no oversized
    // surface is needed to avoid an overflow.
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_shell'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _unlockedStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // No sessions → welcome (ConnectionsView). Vault is NOT a tab; it opens as
    // an overlay from the nav rail (ADR 0022). Its content is absent until then.
    expect(find.text('Vault — Anahtar & Kimlik'), findsNothing);

    // Tap the Vault nav-rail button (by key, not icon — VaultView also paints a
    // vpn_key icon once open).
    await tester.tap(find.byKey(const Key('navVault')));
    await tester.pump();

    // The overlay (header + VaultView) is now shown; VaultView's unique action
    // button proves the body is mounted.
    expect(find.byKey(const Key('overlayClose')), findsOneWidget);
    expect(find.text('Yeni anahtar üret'), findsOneWidget);

    // Esc closes the overlay.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('overlayClose')), findsNothing);
    expect(find.text('Yeni anahtar üret'), findsNothing);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets(
      'dragging the sidebar resize handle updates + clamps the persisted width',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_resize'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => _unlockedStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(sidebarWidthProvider),
        ShellMetrics.sidebarDefaultWidth);

    final handle = find.byKey(const Key('sidebarResizeHandle'));
    expect(handle, findsOneWidget);

    // Drag the handle right by 80px → width grows and persists (clamped).
    await tester.drag(handle, const Offset(80, 0));
    await tester.pump();
    expect(container.read(sidebarWidthProvider),
        ShellMetrics.sidebarDefaultWidth + 80);
    expect(prefs.getDouble('sidebarWidth'),
        ShellMetrics.sidebarDefaultWidth + 80);

    // Drag far right past the max → clamps to 480.
    await tester.drag(handle, const Offset(400, 0));
    await tester.pump();
    expect(container.read(sidebarWidthProvider), ShellMetrics.sidebarMaxWidth);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('dragging the sidebar handle far left collapses the panel',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_resize2'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => _unlockedStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(sidebarVisibleProvider), isTrue);

    // Drag the handle left below the snap threshold (272 → ~152) → collapse.
    await tester.drag(find.byKey(const Key('sidebarResizeHandle')),
        const Offset(-120, 0));
    await tester.pump();

    expect(container.read(sidebarVisibleProvider), isFalse);
    expect(prefs.getBool('sidebarCollapsed'), isTrue);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('picking a theme from the title-bar theme button changes it', (
    tester,
  ) async {
    final tmp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshall_shell2'),
    );
    PathProviderPlatform.instance = _FakePathProvider(tmp!.path);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final store = await tester.runAsync(() => _unlockedStore(tmp));

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWith((ref) async => store!),
      ],
    );
    await tester.runAsync(() => container.read(secureStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Default theme is night
    expect(container.read(themeControllerProvider), AppThemeId.night);

    // The title bar exposes a single theme button (ADR 0009 redesign): open it
    // and pick "Gündüz (Açık)" from the popup.
    await tester.tap(find.byKey(const Key('themeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppThemeId.day.label));
    await tester.pumpAndSettle();

    expect(container.read(themeControllerProvider), AppThemeId.day);
    expect(prefs.getString('themeId'), 'day');

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
