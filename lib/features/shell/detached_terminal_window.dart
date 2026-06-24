import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../theme/app_colors.dart';
import 'window_proxy_protocol.dart';

/// The root widget for a detached terminal window (ADR 0020). It runs in a
/// separate engine, renders an [xterm.Terminal] fed by output proxied from the
/// main window, and sends keystrokes/resize/redock back over the per-tab
/// bidirectional channel. The live SSH session itself never leaves the main
/// isolate.
class DetachedTerminalApp extends StatelessWidget {
  final String channelName;
  final String tabId;
  final String title;

  /// Global terminal font (ADR 0038 D5) inherited from the main window at detach
  /// time, so the detached window matches the in-app font. Defaults preserve the
  /// previous hard-coded values if the args are missing.
  final double fontSize;
  final String fontFamily;

  const DetachedTerminalApp({
    super.key,
    required this.channelName,
    required this.tabId,
    required this.title,
    this.fontSize = 13,
    this.fontFamily = 'JetBrains Mono',
  });

  @override
  Widget build(BuildContext context) {
    const c = AppColors.night;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [c],
        scaffoldBackgroundColor: c.bg,
      ),
      home: DetachedTerminalScreen(
        channelName: channelName,
        tabId: tabId,
        title: title,
        fontSize: fontSize,
        fontFamily: fontFamily,
      ),
    );
  }
}

class DetachedTerminalScreen extends StatefulWidget {
  final String channelName;
  final String tabId;
  final String title;
  final double fontSize;
  final String fontFamily;

  const DetachedTerminalScreen({
    super.key,
    required this.channelName,
    required this.tabId,
    required this.title,
    this.fontSize = 13,
    this.fontFamily = 'JetBrains Mono',
  });

  @override
  State<DetachedTerminalScreen> createState() => _DetachedTerminalScreenState();
}

class _DetachedTerminalScreenState extends State<DetachedTerminalScreen> {
  late final xterm.Terminal _terminal;
  late final WindowMethodChannel _ch;
  String _status = 'ready';

  @override
  void initState() {
    super.initState();
    _terminal = xterm.Terminal(maxLines: 5000);
    _terminal.onOutput = (s) =>
        _send(InputMessage(Uint8List.fromList(utf8.encode(s))));
    _terminal.onResize = (w, h, pw, ph) => _send(ResizeMessage(w, h, pw, ph));
    _ch = WindowMethodChannel(
      widget.channelName,
      mode: ChannelMode.bidirectional,
    );
    _ch.setMethodCallHandler(_onFromMain);
  }

  Future<dynamic> _onFromMain(MethodCall call) async {
    if (call.method != 'msg') return null;
    final msg = decodeWindowMessage(call.arguments as String);
    switch (msg) {
      case OutputMessage(:final data):
      case BacklogMessage(:final data):
        _terminal.write(utf8.decode(data, allowMalformed: true));
      case StatusMessage(:final status):
        if (mounted) setState(() => _status = status);
      case ClosedMessage():
        if (mounted) setState(() => _status = 'closed');
      default:
        break;
    }
    return null;
  }

  void _send(WindowMessage m) =>
      _ch.invokeMethod('msg', m.encode()).catchError((_) => null);

  Future<void> _hideWindow() async {
    try {
      final wc = await WindowController.fromCurrentEngine();
      await wc.hide();
    } catch (_) {}
  }

  /// Release the proxy channel so this (about-to-be-hidden) window stops holding
  /// an engine slot. `desktop_multi_window` 0.3.0 cannot destroy windows, only
  /// hide them, so a hidden window that kept its handler registered would leak a
  /// channel slot; the main side already uses a fresh channel per detach, and
  /// this is the matching window-side cleanup (defense in depth).
  void _releaseChannel() {
    _ch.setMethodCallHandler(null).catchError((_) => null);
  }

  void _redock() {
    _send(RedockRequestedMessage(widget.tabId));
    _releaseChannel();
    _hideWindow();
  }

  @override
  void dispose() {
    _releaseChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const c = AppColors.night;
    final dot = _status == 'ready'
        ? c.green
        : (_status == 'error' ? c.red : c.textDim);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          // The title row is the frameless window's chrome: dragging it moves the
          // detached OS window (ADR 0024). The redock button keeps its own tap.
          DragToMoveArea(
            child: Container(
              height: 40,
              // Reserve the left inset for the macOS traffic lights (same 78px
              // treatment as the main TitleBar): with fullSizeContentView the
              // native buttons overlay this row's top-left, so content starts
              // clear of them (ADR 0024).
              padding: const EdgeInsets.only(left: 78, right: 12),
              color: c.surface,
              child: Row(
                children: [
                  Icon(Icons.terminal_outlined, size: 15, color: c.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.text, fontSize: 13),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: 'Bu terminali ana pencereye geri al',
                    child: TextButton.icon(
                      onPressed: _redock,
                      icon: Icon(
                        Icons.call_received,
                        size: 14,
                        color: c.accent,
                      ),
                      label: Text(
                        'Ana Pencereye Al',
                        style: TextStyle(color: c.accent, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: c.termBg,
              child: xterm.TerminalView(
                _terminal,
                autofocus: true,
                // Inherits the global terminal font from the main window
                // (ADR 0038 D5) instead of hard-coding 13 / 'JetBrains Mono'.
                textStyle: xterm.TerminalStyle(
                  fontSize: widget.fontSize,
                  fontFamily: widget.fontFamily,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
