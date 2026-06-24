import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/shell/shell_metrics.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, SharedPreferences)> make({
    Map<String, Object> seed = const {},
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return (container, prefs);
  }

  test('defaults to 272px, expanded, when nothing is persisted', () async {
    final (container, _) = await make();
    final s = container.read(sidebarControllerProvider);
    expect(s.width, ShellMetrics.sidebarDefaultWidth);
    expect(s.collapsed, isFalse);
    expect(container.read(sidebarVisibleProvider), isTrue);
    expect(container.read(sidebarWidthProvider), 272);
  });

  test('restores a persisted width + collapsed flag', () async {
    final (container, _) = await make(
      seed: {'sidebarWidth': 320.0, 'sidebarCollapsed': true},
    );
    final s = container.read(sidebarControllerProvider);
    expect(s.width, 320);
    expect(s.collapsed, isTrue);
    expect(container.read(sidebarVisibleProvider), isFalse);
  });

  test('setWidth clamps to [200, 480] and persists', () async {
    final (container, prefs) = await make();
    final n = container.read(sidebarControllerProvider.notifier);

    n.setWidth(999);
    expect(container.read(sidebarWidthProvider), 480);
    expect(prefs.getDouble('sidebarWidth'), 480);

    n.setWidth(250);
    expect(container.read(sidebarWidthProvider), 250);
    expect(prefs.getDouble('sidebarWidth'), 250);
    expect(container.read(sidebarVisibleProvider), isTrue);
  });

  test('dragging below the snap threshold collapses (not clamps)', () async {
    final (container, prefs) = await make();
    final n = container.read(sidebarControllerProvider.notifier);

    // 170 < sidebarCollapseSnap (180) → collapse, do not clamp to 200.
    n.setWidth(170);
    expect(container.read(sidebarVisibleProvider), isFalse);
    expect(prefs.getBool('sidebarCollapsed'), isTrue);

    // Re-expanding restores the last usable width (default 272), no flicker.
    n.setCollapsed(false);
    expect(container.read(sidebarWidthProvider), 272);
  });

  test('toggle flips collapsed and persists it', () async {
    final (container, prefs) = await make();
    final n = container.read(sidebarControllerProvider.notifier);

    n.toggle();
    expect(container.read(sidebarVisibleProvider), isFalse);
    expect(prefs.getBool('sidebarCollapsed'), isTrue);

    n.toggle();
    expect(container.read(sidebarVisibleProvider), isTrue);
    expect(prefs.getBool('sidebarCollapsed'), isFalse);
  });
}
