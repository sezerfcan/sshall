import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_controller.dart';

/// Persisted "recently quick-connected" targets (ADR 0034 D4). Mirrors the
/// [SidebarController] sharedPrefs pattern (ADR 0030): a `sharedPrefsProvider`-
/// backed [Notifier] that tolerates a missing/overridden prefs provider (bare
/// test containers) by falling back to in-memory only.
///
/// SECURITY (ADR 0034, critical): only the plain `user@host:port` target string
/// is stored — NEVER a password / passphrase / private key / any secret. The API
/// surface has no field for a secret, so this is also a compile-time guarantee.
final recentTargetsControllerProvider =
    NotifierProvider<RecentTargetsController, List<String>>(
      RecentTargetsController.new,
    );

class RecentTargetsController extends Notifier<List<String>> {
  /// SharedPreferences key holding the recents as a plain `List<String>`.
  static const String _key = 'recentQuickTargets';

  /// Hard cap on the number of remembered targets (most-recent-first LIFO).
  static const int _cap = 10;

  SharedPreferences? _prefs;

  @override
  List<String> build() {
    try {
      _prefs = ref.read(sharedPrefsProvider);
    } catch (_) {
      _prefs = null; // bare container (e.g. some widget tests): in-memory only.
    }
    final saved = _prefs?.getStringList(_key);
    // Defensive: clamp a possibly-oversized persisted list to the cap.
    return saved == null
        ? const <String>[]
        : List<String>.unmodifiable(saved.take(_cap));
  }

  /// Records [target] as the most-recent entry (LIFO): inserts it at the FRONT,
  /// de-duplicates any prior occurrence (moved to front, never doubled), and
  /// prunes to [_cap]. Blank targets are ignored. Persisted via setStringList.
  ///
  /// Only the `user@host:port` string is ever passed here — no secret.
  void add(String target) {
    final t = target.trim();
    if (t.isEmpty) return;
    final next = <String>[t, ...state.where((e) => e != t)];
    final capped = next.length > _cap ? next.sublist(0, _cap) : next;
    state = List<String>.unmodifiable(capped);
    _prefs?.setStringList(_key, capped);
  }

  /// Removes a single [target] (per-row "x" in the suggestions dropdown).
  void remove(String target) {
    if (!state.contains(target)) return;
    final next = state.where((e) => e != target).toList();
    state = List<String>.unmodifiable(next);
    _prefs?.setStringList(_key, next);
  }

  /// Clears the whole history ("Geçmişi temizle" action).
  void clear() {
    if (state.isEmpty) return;
    state = const <String>[];
    _prefs?.setStringList(_key, const <String>[]);
  }
}
