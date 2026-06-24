import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'features/shell/detached_terminal_window.dart';
import 'features/shell/window_detach_service.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A detached terminal window (ADR 0020) reuses this same entrypoint in its own
  // engine; it identifies itself via its WindowController arguments. Guarded so
  // any failure here falls through to the normal app — the main window must
  // always launch.
  if (WindowDetachService.supported) {
    try {
      final wc = await WindowController.fromCurrentEngine();
      final args = wc.arguments.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(wc.arguments) as Map<String, dynamic>;
      if (args['role'] == 'detachedTerminal') {
        runApp(
          DetachedTerminalApp(
            channelName: '${args['channel']}',
            tabId: '${args['tabId']}',
            title: '${args['title'] ?? 'Terminal'}',
            // Inherit the global terminal font from the main window (ADR 0038
            // D5); fall back to the previous hard-coded values if absent.
            fontSize: (args['fontSize'] as num?)?.toDouble() ?? 13,
            fontFamily: '${args['fontFamily'] ?? 'JetBrains Mono'}',
          ),
        );
        // desktop_multi_window registers window_manager's plugin on THIS
        // sub-engine too, but only the main engine runs ensureInitialized()
        // below. The detached title row's DragToMoveArea calls
        // window_manager.startDragging(), which force-unwraps the plugin's
        // _mainWindow — nil on an uninitialized engine → native crash (ADR 0024).
        // Initialize window_manager for this sub-engine so startDragging() drags
        // THIS window. Deferred to after the first frame so the FlutterView is
        // attached to its NSWindow (the native getter force-unwraps the window).
        // Safe to coexist: desktop_multi_window handles window close via
        // NotificationCenter, not the NSWindow delegate window_manager sets.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await windowManager.ensureInitialized();
          } catch (_) {
            // Best-effort: a failure here only means title-row drag is inert,
            // never fatal — the detached window still works otherwise.
          }
        });
        return;
      }
    } catch (_) {
      // Not a sub-window (or multi-window unavailable): run the normal app.
    }
  }

  final prefs = await SharedPreferences.getInstance();

  // Main shell window only (detached sub-windows already returned above):
  // switch to a frameless chrome (ADR 0024). window_manager governs ONLY this
  // engine's window; detached windows are made frameless Swift-side.
  if (WindowDetachService.supported) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden, // native bar hidden
      windowButtonVisibility: true, // macOS traffic lights stay visible
      minimumSize: Size(720, 520), // ADR 0021
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const SshallApp(),
    ),
  );
}
