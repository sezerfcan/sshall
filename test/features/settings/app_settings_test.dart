import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/settings/app_settings.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer() async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AppSettings defaults', () {
    test('a fresh value object carries the documented defaults', () {
      const s = AppSettings();
      expect(s.terminalFontSize, 13);
      expect(s.terminalFontFamily, 'JetBrains Mono');
      expect(s.defaultPort, 22);
      expect(s.defaultUsername, '');
      expect(s.keepAliveSeconds, 0);
      expect(s.confirmOnCloseLiveSession, isTrue);
      expect(s.openOnLaunch, OpenOnLaunch.welcome);
    });

    test('the controller starts at defaults with empty prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final container = await makeContainer();
      final s = container.read(appSettingsControllerProvider);
      expect(s, const AppSettings());
    });
  });

  group('persistence', () {
    test(
      'setTerminalFontSize persists and reloads in a new container',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c1 = await makeContainer();
        c1.read(appSettingsControllerProvider.notifier).setTerminalFontSize(16);
        expect(c1.read(appSettingsControllerProvider).terminalFontSize, 16);

        // A brand-new container reading the same (mock) prefs must observe 16.
        final c2 = await makeContainer();
        expect(c2.read(appSettingsControllerProvider).terminalFontSize, 16);
      },
    );

    test('font family / port / username round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final c1 = await makeContainer();
      final n = c1.read(appSettingsControllerProvider.notifier);
      n.setTerminalFontFamily('IBM Plex Mono');
      n.setDefaultPort(2222);
      n.setDefaultUsername('deploy');
      n.setKeepAliveSeconds(30);
      n.setConfirmOnCloseLiveSession(false);
      n.setOpenOnLaunch(OpenOnLaunch.last);

      final c2 = await makeContainer();
      final s = c2.read(appSettingsControllerProvider);
      expect(s.terminalFontFamily, 'IBM Plex Mono');
      expect(s.defaultPort, 2222);
      expect(s.defaultUsername, 'deploy');
      expect(s.keepAliveSeconds, 30);
      expect(s.confirmOnCloseLiveSession, isFalse);
      expect(s.openOnLaunch, OpenOnLaunch.last);
    });
  });

  group('clamp / validation', () {
    test('font size clamps to [8, 32]', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await makeContainer();
      final n = c.read(appSettingsControllerProvider.notifier);
      n.setTerminalFontSize(99);
      expect(c.read(appSettingsControllerProvider).terminalFontSize, 32);
      n.setTerminalFontSize(2);
      expect(c.read(appSettingsControllerProvider).terminalFontSize, 8);
    });

    test('out-of-range port is rejected (value stays valid)', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await makeContainer();
      final n = c.read(appSettingsControllerProvider.notifier);
      n.setDefaultPort(2222);
      n.setDefaultPort(70000); // invalid → rejected
      expect(c.read(appSettingsControllerProvider).defaultPort, 2222);
      n.setDefaultPort(0); // invalid → rejected
      expect(c.read(appSettingsControllerProvider).defaultPort, 2222);
    });

    test('unknown font family is rejected', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await makeContainer();
      final n = c.read(appSettingsControllerProvider.notifier);
      n.setTerminalFontFamily('Comic Sans');
      expect(
        c.read(appSettingsControllerProvider).terminalFontFamily,
        'JetBrains Mono',
      );
    });

    test('keepalive clamps to [0, max]', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await makeContainer();
      final n = c.read(appSettingsControllerProvider.notifier);
      n.setKeepAliveSeconds(-5);
      expect(c.read(appSettingsControllerProvider).keepAliveSeconds, 0);
      n.setKeepAliveSeconds(999999);
      expect(c.read(appSettingsControllerProvider).keepAliveSeconds, 3600);
    });
  });

  group('reset', () {
    test('reset() restores defaults and clears the persisted keys', () async {
      SharedPreferences.setMockInitialValues({});
      final c1 = await makeContainer();
      final n = c1.read(appSettingsControllerProvider.notifier);
      n.setTerminalFontSize(20);
      n.setDefaultPort(2222);
      n.setDefaultUsername('deploy');
      n.reset();
      expect(c1.read(appSettingsControllerProvider), const AppSettings());

      // The persisted keys are gone, so a fresh container also reads defaults.
      final c2 = await makeContainer();
      expect(c2.read(appSettingsControllerProvider), const AppSettings());
    });
  });

  group('defensive parse', () {
    test(
      'a corrupt/out-of-range stored value falls back to a default',
      () async {
        // Seed an invalid port + an unknown family directly into prefs.
        SharedPreferences.setMockInitialValues({
          'defaultPort': 999999,
          'terminalFontFamily': 'Nonexistent Mono',
          'terminalFontSize': 500,
        });
        final c = await makeContainer();
        final s = c.read(appSettingsControllerProvider);
        expect(s.defaultPort, 22); // invalid → default
        expect(s.terminalFontFamily, 'JetBrains Mono'); // unknown → default
        expect(s.terminalFontSize, 32); // clamped
      },
    );
  });

  group('in-memory fallback', () {
    test('a bare container (no prefs override) works in-memory', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(appSettingsControllerProvider.notifier);
      n.setTerminalFontSize(18);
      expect(
        container.read(appSettingsControllerProvider).terminalFontSize,
        18,
      );
    });
  });
}
