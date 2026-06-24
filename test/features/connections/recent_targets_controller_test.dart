import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/connections/recent_targets_controller.dart';
import 'package:sshall/theme/theme_controller.dart';

/// Unit coverage for the recents controller (ADR 0034 D4): most-recent-first
/// LIFO, dedup on insert, cap pruning, remove/clear, sharedPrefs round-trip,
/// in-memory fallback for a bare container, and the no-secret guarantee (the
/// stored values are exactly the plain target strings given).
void main() {
  Future<ProviderContainer> seeded(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('add inserts most-recent-first; re-adding the same target dedups', () {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(recentTargetsControllerProvider.notifier);

    ctrl.add('root@a.com:22');
    ctrl.add('root@b.com:22');
    expect(c.read(recentTargetsControllerProvider), [
      'root@b.com:22',
      'root@a.com:22',
    ]);

    // Re-adding an existing target moves it to the front WITHOUT duplicating.
    ctrl.add('root@a.com:22');
    expect(c.read(recentTargetsControllerProvider), [
      'root@a.com:22',
      'root@b.com:22',
    ]);
  });

  test('exceeding the cap (10) drops the oldest (LIFO pruning)', () {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(recentTargetsControllerProvider.notifier);

    for (var i = 0; i < 12; i++) {
      ctrl.add('user@host$i.com:22');
    }
    final list = c.read(recentTargetsControllerProvider);
    expect(list.length, 10);
    // Newest (host11) at front; the two oldest (host0/host1) were pruned.
    expect(list.first, 'user@host11.com:22');
    expect(list.contains('user@host0.com:22'), isFalse);
    expect(list.contains('user@host1.com:22'), isFalse);
  });

  test('remove drops a single target; clear empties; both persist', () async {
    final c = await seeded({});
    final ctrl = c.read(recentTargetsControllerProvider.notifier);
    ctrl.add('root@a.com:22');
    ctrl.add('root@b.com:22');

    ctrl.remove('root@a.com:22');
    expect(c.read(recentTargetsControllerProvider), ['root@b.com:22']);

    final prefs = c.read(sharedPrefsProvider);
    expect(prefs.getStringList('recentQuickTargets'), ['root@b.com:22']);

    ctrl.clear();
    expect(c.read(recentTargetsControllerProvider), isEmpty);
    expect(prefs.getStringList('recentQuickTargets'), isEmpty);
  });

  test('state round-trips through setStringList/getStringList', () async {
    final c1 = await seeded({});
    c1.read(recentTargetsControllerProvider.notifier).add('root@a.com:22');
    c1.read(recentTargetsControllerProvider.notifier).add('root@b.com:22');

    // Rebuild a fresh container over the SAME prefs instance → same list.
    final prefs = c1.read(sharedPrefsProvider);
    final c2 = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    expect(c2.read(recentTargetsControllerProvider), [
      'root@b.com:22',
      'root@a.com:22',
    ]);
  });

  test('bare container without prefs override does not crash (in-memory)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // No sharedPrefsProvider override: build() must fall back to in-memory.
    expect(c.read(recentTargetsControllerProvider), isEmpty);
    c.read(recentTargetsControllerProvider.notifier).add('root@a.com:22');
    expect(c.read(recentTargetsControllerProvider), ['root@a.com:22']);
  });

  test('stores ONLY the given target string (no secret leak)', () async {
    final c = await seeded({});
    c.read(recentTargetsControllerProvider.notifier).add('root@a.com:2222');
    final stored = c
        .read(sharedPrefsProvider)
        .getStringList('recentQuickTargets');
    // The persisted value is verbatim the target — no password/passphrase/key.
    expect(stored, ['root@a.com:2222']);
    expect(stored!.single.contains('password'), isFalse);
  });

  test('blank targets are ignored', () {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(recentTargetsControllerProvider.notifier).add('   ');
    expect(c.read(recentTargetsControllerProvider), isEmpty);
  });
}
