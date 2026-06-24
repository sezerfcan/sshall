import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/settings/app_settings.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';
import 'package:sshall/theme/theme_controller.dart';

class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  @override
  Stream<WorkerEvent> get events => _c.stream;
  @override
  WorkerEvent? get currentLifecycle => null;
  @override
  void sendInput(Uint8List data) {}
  @override
  void resize(int w, int h, int pw, int ph) {}
  @override
  void decideHostKey(bool accept) {}
  @override
  Uint8List takeOutputBacklog() => Uint8List(0);
  @override
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new terminal tab initialises its font size from the global default '
      '(not the hard-coded 13)', () async {
    SharedPreferences.setMockInitialValues({'terminalFontSize': 18});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // Sanity: the setting loaded 18.
    expect(container.read(appSettingsControllerProvider).terminalFontSize, 18);

    final tabs = container.read(tabsControllerProvider.notifier);
    final id = tabs.openTerminal(_FakeSession(), 'web:22');
    final ctrl = tabs.controllerFor(id)!;
    // The new tab started at the global default, not kFontDefault (13).
    expect(ctrl.fontSize.value, 18);
  });

  test(
    'with no setting, a new tab still starts at the default font size 13',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final tabs = container.read(tabsControllerProvider.notifier);
      final id = tabs.openTerminal(_FakeSession(), 'web:22');
      expect(tabs.controllerFor(id)!.fontSize.value, 13);
    },
  );
}
