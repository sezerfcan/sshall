import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../services/ssh/ssh_messages.dart';
import '../../services/ssh/terminal_session.dart';
import 'session_status.dart';

const double kFontDefault = 13.0;
const double kFontMin = 8.0;
const double kFontMax = 32.0;
const double kFontStep = 1.0;

/// Owns the live state of a single terminal tab: the xterm [Terminal]
/// (scrollback), the worker-event subscription, the connection [status] and the
/// [fontSize]. Decoupled from the widget tree so a tab survives tab/group
/// switches without losing scrollback, and so the session can later move to a
/// separate window (ADR 0017, Slice 2).
///
/// The worker isolate protocol (`SshStatus`, `ErrorEvent.code`, `ClosedEvent`)
/// is UNCHANGED (ADR 0032 D1); this controller translates those raw events into
/// a rich [SessionStatus] value object — the single source of truth every
/// surface reads from.
class TerminalSessionController {
  /// [hostPort] is the human `host:port` shown in the connecting pane / status
  /// bar (D2/D7); null for sessions without a network endpoint (e.g. local
  /// Docker exec). [reconnectThunk] re-runs the full connect flow (host-key
  /// dialog included) and rebinds the resulting session onto THIS controller via
  /// [rebind], reusing the same [terminal] so scrollback is preserved (D5).
  TerminalSessionController(
    this.session, {
    this.hostPort,
    Future<void> Function()? reconnectThunk,
    this.onEdit,
    double? initialFontSize,
  }) : _reconnectThunk = reconnectThunk {
    terminal = xterm.Terminal(maxLines: 5000);
    if (initialFontSize != null) {
      // The global default terminal font size (ADR 0038 D5). New tabs start
      // here instead of the hard-coded [kFontDefault]; per-tab +/−/0 zoom still
      // applies on top (clamped to [kFontMin, kFontMax]).
      fontSize.value = initialFontSize.clamp(kFontMin, kFontMax).toDouble();
    }
    _attach();
  }

  /// The live session. Replaced by [rebind] on a manual reconnect.
  TerminalSession session;
  late final xterm.Terminal terminal;

  /// The human `host:port` for this session (null = no network endpoint).
  final String? hostPort;

  /// The negotiated cipher once connected, when known. The worker protocol does
  /// not report it (D1: protocol unchanged), so this stays null for now; the
  /// status bar / host cards omit the cipher cell when null rather than showing
  /// a stale placeholder (deviation noted — full cipher plumbing is pass-2).
  final ValueNotifier<String?> cipher = ValueNotifier<String?>(null);

  Future<void> Function()? _reconnectThunk;

  /// Opens the edit dialog for this session's connection (error card
  /// `[Bağlantıyı Düzenle]`, ADR 0032 D3). Null for sessions with no editable
  /// connection (e.g. Docker exec / endpoint-less sessions).
  final VoidCallback? onEdit;

  /// Rich session lifecycle (ADR 0032 D1). Starts in `connecting`: the tab is
  /// opened IMMEDIATELY on connect (D2), before the worker reports anything, and
  /// the in-pane connecting overlay reads this until `connected`.
  final ValueNotifier<SessionStatus> status = ValueNotifier<SessionStatus>(
    const SessionStatus.connecting(),
  );
  final ValueNotifier<double> fontSize = ValueNotifier<double>(kFontDefault);

  /// Optional taps used when this session is mirrored into a detached OS window
  /// (ADR 0020): raw worker output bytes and status changes are forwarded to the
  /// window over the proxy bridge. Null when not detached; the controller keeps
  /// rendering to its own [terminal] regardless, so re-docking shows full
  /// scrollback. The status tap carries the legacy string token (`.state.name`)
  /// for backward compatibility with the window proxy — detached-window parity
  /// for the rich model is pass-2 (ADR 0032 scope-out).
  void Function(Uint8List data)? onRawOutput;
  void Function(String status)? onStatusChange;

  StreamSubscription<WorkerEvent>? _sub;
  bool _disposed = false;

  /// True once the user explicitly closed/cancelled this session. Set BEFORE the
  /// CloseCommand is sent so the subsequent ClosedEvent is recorded as a
  /// user-initiated close (no reconnect offered) rather than an unexpected drop
  /// (ADR 0032 D1/D5).
  bool _userClosing = false;

  void _attach() {
    terminal.onOutput = (data) =>
        session.sendInput(Uint8List.fromList(utf8.encode(data)));
    terminal.onResize = (w, h, pw, ph) => session.resize(w, h, pw, ph);

    final backlog = session.takeOutputBacklog();
    if (backlog.isNotEmpty) {
      terminal.write(utf8.decode(backlog, allowMalformed: true));
    }

    // Replay the last lifecycle event the session already saw before this
    // listener attached (broadcast streams drop pre-subscription events). Guards
    // the connect→handoff race so a status reached before attach is not lost.
    final pending = session.currentLifecycle;
    if (pending != null) _applyEvent(pending);

    _sub = session.events.listen(_applyEvent);
  }

  void _applyEvent(WorkerEvent e) {
    switch (e) {
      case OutputEvent(:final data):
        terminal.write(utf8.decode(data, allowMalformed: true));
        onRawOutput?.call(data);
      case StatusEvent(status: final s):
        _set(switch (s) {
          SshStatus.connecting => const SessionStatus.connecting(),
          SshStatus.authenticating => const SessionStatus.authenticating(),
          SshStatus.ready => const SessionStatus.connected(),
          // A bare `closed` status (no preceding error) is a normal end.
          SshStatus.closed =>
            _userClosing
                ? const SessionStatus.closedByUser()
                : const SessionStatus.dropped(),
        });
      case ErrorEvent(:final code, :final message):
        // No raw red `[sshall] ...` line is written to the terminal anymore
        // (ADR 0032 D3): the persistent in-pane error card surfaces this. The
        // prior scrollback is left untouched so it stays visible under the
        // card (freeze).
        _set(classifyError(code, message));
      case ClosedEvent():
        // An error already set a richer error status; do not overwrite it with
        // a generic disconnect (the card must keep the cause). Only a clean
        // close (or a drop with no prior error) produces a disconnected status.
        if (!status.value.isError) {
          _set(
            _userClosing
                ? const SessionStatus.closedByUser()
                : const SessionStatus.dropped(),
          );
        }
      case HostKeyRequestEvent():
        break; // Handled by the connect orchestrator (host-key dialog).
    }
  }

  void _set(SessionStatus s) {
    status.value = s;
    onStatusChange?.call(s.state.name);
  }

  /// Re-runs the connect flow for this tab (host-key dialog included) and
  /// rebinds the new session via [rebind]. Reuses the stored connection params,
  /// the same [terminal] (scrollback preserved) and the same controller (D5).
  /// Never auto-invoked — only reached from the explicit manual reconnect
  /// affordances (error card / status-bar dot / tab menu); after an auth or
  /// host-key-mismatch failure there is no auto path, so security holds.
  Future<void> reconnect() async {
    final thunk = _reconnectThunk;
    if (thunk == null || _disposed) return;
    await thunk();
  }

  /// Whether a manual reconnect is wired for this controller.
  bool get canReconnect => _reconnectThunk != null;

  /// Wire (or rewire) the manual-reconnect thunk after construction. Used by the
  /// connect orchestrator, which only knows the tab id (needed by the thunk to
  /// rebind into the same tab) AFTER [openTerminal] returns it.
  void bindReconnect(Future<void> Function() thunk) => _reconnectThunk = thunk;

  /// Swap in a freshly-connected [next] session (manual reconnect path). Cancels
  /// the old subscription, closes the old session, re-attaches event handling to
  /// [next] and resets [status] to `connecting`. The same [terminal] is reused so
  /// the scrollback survives the reconnect (D5).
  Future<void> rebind(
    TerminalSession next, {
    Future<void> Function()? reconnectThunk,
  }) async {
    if (_disposed) {
      await next.close().catchError((_) {});
      return;
    }
    await _sub?.cancel();
    _sub = null;
    final old = session;
    _userClosing = false;
    session = next;
    if (reconnectThunk != null) _reconnectThunk = reconnectThunk;
    _set(const SessionStatus.connecting());
    _attach();
    // Close the previous session AFTER re-attaching so a fast new event is never
    // lost; the old socket/isolate is torn down in the background.
    unawaited(old.close().catchError((_) {}));
  }

  void zoomIn() => _setFont(fontSize.value + kFontStep);
  void zoomOut() => _setFont(fontSize.value - kFontStep);
  void zoomReset() => _setFont(kFontDefault);

  void _setFont(double v) =>
      fontSize.value = v.clamp(kFontMin, kFontMax).toDouble();

  /// Cancels the subscription and closes the session. Idempotent. Marks the
  /// close as user-initiated so the ClosedEvent is not mistaken for a drop.
  ///
  /// The [ValueNotifier]s are intentionally NOT disposed here: close() is called
  /// from TabsController right as the tab is removed, and a still-mounted
  /// ValueListenableBuilder would crash on a disposed notifier during the unmount
  /// race. They are released by GC instead.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _userClosing = true;
    await _sub?.cancel();
    _sub = null;
    await session.close().catchError((_) {});
  }
}
