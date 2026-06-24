import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../theme/context_ext.dart';
import '../settings/app_settings.dart';
import '../shell/shell_state.dart';
import 'connecting_pane.dart';
import 'connection_error_card.dart';
import 'session_status.dart';
import 'terminal_session_controller.dart';
import 'terminal_status_bar.dart';

/// Renders ONE terminal session (xterm canvas + status bar). The tab strip lives
/// at the group level (ShellTabBar), so this widget no longer draws tabs. All
/// live state comes from [controller]; switching tabs/groups never rebuilds the
/// session itself.
///
/// ADR 0032 D2/D3: the pane is LAYERED on the [SessionStatus] —
/// connecting/authenticating shows a centered [ConnectingPane] over the (empty)
/// terminal; connected shows the terminal; error / unexpected disconnect freezes
/// the terminal (prior scrollback stays visible underneath) and overlays a
/// persistent [ConnectionErrorCard]. A user-initiated close shows no card.
///
/// Name clash note: xterm's widget is also named `TerminalView`; it is used via
/// the `xterm.` alias.
class TerminalView extends ConsumerWidget {
  final TerminalSessionController controller;
  const TerminalView({super.key, required this.controller});

  /// The tab id owning this controller (so cancel can close the right tab).
  String? _tabIdFor(WidgetRef ref) {
    final n = ref.read(tabsControllerProvider.notifier);
    for (final entry in ref.read(tabsControllerProvider).tabs.keys) {
      if (n.controllerFor(entry) == controller) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The global terminal font family (ADR 0038 D5). The terminal ACTUALLY uses
    // this setting instead of the old hard-coded 'JetBrains Mono'.
    final fontFamily = ref.watch(
      appSettingsControllerProvider.select((s) => s.terminalFontFamily),
    );
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: context.c.termBg,
            child: ValueListenableBuilder<SessionStatus>(
              valueListenable: controller.status,
              builder: (context, status, __) {
                // The xterm canvas is always built (kept mounted) so scrollback
                // survives state transitions and stays visible under the error
                // card (freeze, D3).
                final canvas = ValueListenableBuilder<double>(
                  valueListenable: controller.fontSize,
                  builder: (_, size, __) => xterm.TerminalView(
                    controller.terminal,
                    textStyle: xterm.TerminalStyle(
                      fontSize: size,
                      fontFamily: fontFamily,
                    ),
                  ),
                );

                Widget? overlay;
                if (status.isConnecting) {
                  overlay = ConnectingPane(
                    status: status,
                    hostPort: controller.hostPort ?? '',
                    onCancel: () {
                      final id = _tabIdFor(ref);
                      if (id != null) {
                        ref.read(tabsControllerProvider.notifier).close(id);
                      }
                    },
                  );
                } else if (status.isError ||
                    (status.state == SessionState.disconnected &&
                        !status.userInitiated)) {
                  // error OR unexpected drop → persistent card (D3). A
                  // user-initiated close shows nothing (the tab is closing).
                  overlay = ConnectionErrorCard(
                    status: status,
                    hostPort: controller.hostPort ?? '',
                    onRetry: controller.reconnect,
                    onEdit: controller.onEdit,
                  );
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    canvas,
                    if (overlay != null) Positioned.fill(child: overlay),
                  ],
                );
              },
            ),
          ),
        ),
        ValueListenableBuilder<SessionStatus>(
          valueListenable: controller.status,
          builder: (_, status, __) => ValueListenableBuilder<String?>(
            valueListenable: controller.cipher,
            builder: (_, cipher, __) => ValueListenableBuilder<double>(
              valueListenable: controller.fontSize,
              builder: (_, size, __) => TerminalStatusBar(
                status: status,
                hostPort: controller.hostPort ?? '',
                cipher: cipher,
                fontSize: size,
                onReconnect: controller.canReconnect
                    ? controller.reconnect
                    : null,
                onZoomIn: controller.zoomIn,
                onZoomOut: controller.zoomOut,
                onZoomReset: controller.zoomReset,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
