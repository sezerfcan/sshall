import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'shell_state.dart';
import 'window_proxy_protocol.dart';

/// Main-side bridge for "Move terminal into a new window" (ADR 0020, Model 2).
///
/// The live SSH session stays in the main isolate; a detached window runs in its
/// own engine and only renders + proxies I/O over a per-tab **bidirectional**
/// [WindowMethodChannel]. This service opens the window, pairs the channel, and
/// forwards bytes/status to it (via the controller's proxy taps) while routing
/// input/resize/close/redock back.
///
/// All cross-window calls are wrapped so a transport failure can never crash the
/// main window. The codec ([window_proxy_protocol]) and the detach/redock state
/// machine ([TabsController.detachTab]/redockTab/disposeDetached) are unit-tested
/// independently; this glue is build-verified.
class WindowDetachService {
  WindowDetachService._();
  static final WindowDetachService instance = WindowDetachService._();

  TabsController? _tabs;
  final Map<String, WindowMethodChannel> _channels = {};

  /// Resolves the current global terminal font (size, family) so a detached
  /// window opens with the SAME font as in-app tabs (ADR 0038 D5). Set by
  /// [AppShell] via [bindFont]; defaults to (13, 'JetBrains Mono') until bound.
  (double, String) Function()? _fontResolver;

  /// Monotonic detach counter. The proxy channel name carries this so each
  /// detach gets a FRESH channel — `desktop_multi_window` (0.3.0) can only
  /// `hide()` windows, never destroy them, and a bidirectional channel allows at
  /// most two engines. Reusing one name per tab let a hidden (but still
  /// registered) zombie window keep a slot, so a *second* detach could not pair
  /// its new window — the re-dock message was then silently dropped and the tab
  /// "vanished". A unique name per detach sidesteps the limit entirely.
  int _detachSeq = 0;

  /// Bind the controller this service operates on (called by [AppShell]).
  void bind(TabsController tabs) => _tabs = tabs;

  /// Bind a resolver for the current global terminal font (ADR 0038 D5) so a
  /// detached window inherits the live font size + family.
  void bindFont((double, String) Function() resolver) =>
      _fontResolver = resolver;

  /// Whether detaching to a separate OS window is available here (desktop only).
  static bool get supported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Base channel name for [tabId] (a per-detach suffix is appended at detach
  /// time — see [_detachSeq]).
  static String channelNameFor(String tabId) => 'sshall/proxy/$tabId';

  /// Detach [tabId] (titled [title]) into a new OS window.
  Future<void> detachToWindow(String tabId, String title) async {
    final tabs = _tabs;
    if (tabs == null || !supported) return;
    final ctrl = tabs.controllerFor(tabId);
    if (ctrl == null) return;
    if (_channels.containsKey(tabId)) return; // already detached

    // Fresh channel per detach so a previously-hidden window can never block the
    // new window from pairing (see [_detachSeq]).
    final channelName = '${channelNameFor(tabId)}/${_detachSeq++}';

    // Pair the channel before opening the window so the window can reach us the
    // moment it boots.
    final ch = WindowMethodChannel(
      channelName,
      mode: ChannelMode.bidirectional,
    );
    _channels[tabId] = ch;
    await ch.setMethodCallHandler((call) => _onFromWindow(tabId, call));

    tabs.detachTab(tabId);

    void send(WindowMessage m) {
      ch.invokeMethod('msg', m.encode()).catchError((_) => null);
    }

    ctrl.onRawOutput = (data) => send(OutputMessage(data));
    ctrl.onStatusChange = (s) => send(StatusMessage(s));

    // Carry the live global terminal font into the detached window so it opens
    // with the same size + family the in-app tabs use (ADR 0038 D5).
    final (fontSize, fontFamily) =
        _fontResolver?.call() ?? (13.0, 'JetBrains Mono');

    try {
      final window = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'role': 'detachedTerminal',
            'tabId': tabId,
            'title': title,
            'channel': channelName,
            'fontSize': fontSize,
            'fontFamily': fontFamily,
          }),
          hiddenAtLaunch: false,
        ),
      );
      await window.show();
      // Prime the window with the legacy string token (rich-model parity for
      // detached windows is pass-2, ADR 0032 scope-out).
      send(StatusMessage(ctrl.status.value.state.name));
    } catch (_) {
      // Window failed to open: re-dock so the tab/session is never lost.
      _teardown(tabId);
      tabs.redockTab(tabId);
    }
  }

  Future<dynamic> _onFromWindow(String tabId, MethodCall call) async {
    if (call.method != 'msg') return null;
    final tabs = _tabs;
    if (tabs == null) return null;
    final ctrl = tabs.controllerFor(tabId);
    final msg = decodeWindowMessage(call.arguments as String);
    switch (msg) {
      case InputMessage(:final data):
        ctrl?.session.sendInput(data);
      case ResizeMessage(
        :final cols,
        :final rows,
        :final pixelWidth,
        :final pixelHeight,
      ):
        ctrl?.session.resize(cols, rows, pixelWidth, pixelHeight);
      case RedockRequestedMessage():
        _teardown(tabId);
        tabs.redockTab(tabId);
      case RequestCloseMessage(:final keepSession):
        _teardown(tabId);
        if (keepSession) {
          tabs.redockTab(tabId);
        } else {
          await tabs.disposeDetached(tabId);
        }
      default:
        break;
    }
    return null;
  }

  void _teardown(String tabId) {
    _tabs?.controllerFor(tabId)
      ?..onRawOutput = null
      ..onStatusChange = null;
    final ch = _channels.remove(tabId);
    ch?.setMethodCallHandler(null);
  }
}
