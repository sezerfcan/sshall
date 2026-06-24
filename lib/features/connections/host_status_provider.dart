import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/shell_state.dart';
import '../terminal/session_status.dart';

/// Aggregate, live host-status lookup (ADR 0032 D6): maps a connection's
/// `host:port` to the [SessionStatus] of its open terminal session (if any),
/// derived from [TabsController]'s live controllers.
///
/// Reactive on two axes: it rebuilds when tabs open/close (it watches
/// [tabsControllerProvider]) AND when any live session's status changes (it
/// attaches a listener to each controller's `status` notifier and re-emits).
/// Connection-manager surfaces (HostCard / HostDetailCard / sidebar) watch this
/// to reflect the real state instead of a hard-coded "Bağlı değil".
///
/// When several sessions share a `host:port`, the "most active" status wins
/// (connected > connecting > error > disconnected) so a host with one live shell
/// reads as connected even if another tab to it just dropped.
final hostStatusProvider =
    NotifierProvider<HostStatusNotifier, Map<String, SessionStatus>>(
      HostStatusNotifier.new,
    );

class HostStatusNotifier extends Notifier<Map<String, SessionStatus>> {
  final List<ValueNotifier<SessionStatus>> _watched = [];

  @override
  Map<String, SessionStatus> build() {
    // Rebuild whenever tabs open/close (the set of live controllers changes).
    ref.watch(tabsControllerProvider);
    final tabs = ref.read(tabsControllerProvider.notifier);

    // (Re)attach listeners to the current live controllers so a status flip
    // (connecting → connected → disconnected) re-emits the aggregate map.
    _detachAll();
    for (final ctrl in tabs.liveControllers) {
      final n = ctrl.status;
      void listener() => _recompute();
      n.addListener(listener);
      _watched.add(n);
      // Track the (notifier, listener) pair for clean removal.
      _listeners[n] = listener;
    }
    ref.onDispose(_detachAll);

    return _compute(tabs);
  }

  final Map<ValueNotifier<SessionStatus>, VoidCallback> _listeners = {};

  void _detachAll() {
    for (final n in _watched) {
      final l = _listeners.remove(n);
      if (l != null) n.removeListener(l);
    }
    _watched.clear();
  }

  void _recompute() {
    final tabs = ref.read(tabsControllerProvider.notifier);
    state = _compute(tabs);
  }

  Map<String, SessionStatus> _compute(TabsController tabs) {
    final map = <String, SessionStatus>{};
    for (final ctrl in tabs.liveControllers) {
      final hp = ctrl.hostPort;
      if (hp == null || hp.isEmpty) continue;
      final s = ctrl.status.value;
      final existing = map[hp];
      if (existing == null || _rank(s) > _rank(existing)) {
        map[hp] = s;
      }
    }
    return map;
  }

  /// Priority so the most-active session for a host wins the aggregate.
  int _rank(SessionStatus s) => switch (s.state) {
    SessionState.connected => 4,
    SessionState.connecting => 3,
    SessionState.authenticating => 3,
    SessionState.error => 2,
    SessionState.disconnected => 1,
  };
}

/// The live status for [hostPort], or null when no session targets it (idle).
SessionStatus? hostStatusFor(WidgetRef ref, String hostPort) =>
    ref.watch(hostStatusProvider)[hostPort];
