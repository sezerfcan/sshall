import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Thin seam over the OS window so the title bar's move/zoom controls are
/// testable without driving the real window_manager plugin (ADR 0014 pattern,
/// ADR 0024).
abstract class WindowChrome {
  /// Begin an interactive window move (dragging the title bar).
  Future<void> startDragging();

  /// Toggle the main window between maximized (zoomed) and restored.
  Future<void> toggleMaximize();

  /// Mirror the active session into the OS window title (ADR 0039 D1) so
  /// Mission Control / the window switcher show 'sshall — <session>' (or plain
  /// 'sshall' on the home surface). A pure no-op on a bare/test container.
  Future<void> setTitle(String title);

  /// Whether the OS window is currently in macOS fullscreen, where the native
  /// traffic lights are hidden (ADR 0039 D5). Drives the title bar's left
  /// gutter so it collapses to zero instead of reserving dead space. Defaults to
  /// `false` (a safe no-op) when no window_manager channel is present (e.g.
  /// under flutter_test or a not-yet-ready engine).
  Future<bool> isFullScreen();
}

/// Production implementation backed by window_manager (main engine only).
class WindowManagerChrome implements WindowChrome {
  const WindowManagerChrome();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> setTitle(String title) async {
    // The OS-title mirror (ADR 0039 D1) fires on mount, before any gesture, so
    // unlike the drag/zoom methods it can run in a context where the
    // window_manager channel is absent (widget tests that pump the real shell,
    // or a not-yet-ready engine). Swallow that one case so the mirror is a safe
    // no-op there; any other failure still surfaces.
    try {
      await windowManager.setTitle(title);
    } on MissingPluginException {
      // No window_manager channel (e.g. under flutter_test) — nothing to do.
    }
  }

  @override
  Future<bool> isFullScreen() async {
    // Like setTitle, this can be queried on mount before any gesture, so the
    // window_manager channel may be absent (flutter_test, a not-yet-ready
    // engine). Treat that as "not fullscreen" so the gutter reserves its normal
    // width; any other failure still surfaces.
    try {
      return await windowManager.isFullScreen();
    } on MissingPluginException {
      return false;
    }
  }
}

final windowChromeProvider = Provider<WindowChrome>(
  (ref) => const WindowManagerChrome(),
);

/// Reactive macOS fullscreen state for the title bar's left gutter (ADR 0039
/// D5). Seeds from [WindowChrome.isFullScreen] and then flips on
/// window_manager's enter/leave-fullscreen events, so the 78px traffic-light
/// gutter collapses to zero exactly while the native lights are hidden — no
/// dead left inset in fullscreen. Defaults to `false` and stays inert (no
/// listener attached) when no window_manager channel is present (flutter_test),
/// so the non-fullscreen layout is unchanged there.
final fullScreenProvider = NotifierProvider<FullScreenNotifier, bool>(
  FullScreenNotifier.new,
);

/// Tracks macOS fullscreen by mixing in [WindowListener]. Attaches to
/// window_manager only when the channel is live; under flutter_test the
/// attach/seed are best-effort no-ops, so the value stays `false`.
class FullScreenNotifier extends Notifier<bool> with WindowListener {
  bool _attached = false;

  @override
  bool build() {
    _attach();
    ref.onDispose(_detach);
    return false;
  }

  void _attach() {
    try {
      windowManager.addListener(this);
      _attached = true;
      // Seed the initial value; the window may already be fullscreen on launch.
      ref
          .read(windowChromeProvider)
          .isFullScreen()
          .then((v) {
            if (_attached) state = v;
          })
          .catchError((_) {
            // Best-effort seed: degrade to the non-fullscreen default.
          });
    } on MissingPluginException {
      // No window_manager channel (flutter_test) — stay inert at `false`.
    } catch (_) {
      // Any other attach failure: degrade to the non-fullscreen default.
    }
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    try {
      windowManager.removeListener(this);
    } catch (_) {
      // Best-effort detach.
    }
  }

  @override
  void onWindowEnterFullScreen() => state = true;

  @override
  void onWindowLeaveFullScreen() => state = false;
}
