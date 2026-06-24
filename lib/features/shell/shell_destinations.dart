import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shell_overlay.dart';
import 'shell_state.dart';

/// The four left-rail navigation destinations (ADR 0030 D1/D2). The two top
/// "places" (connections, sftp) drive the panel/home; the two bottom "tools"
/// (vault, settings) are overlay toggles. Mapped to ⌘/Ctrl+1..4 (D7).
enum ShellDestination { connections, sftp, vault, settings }

/// Whether [dest] is currently the active destination, given the live shell
/// state. Used by the rail for its active visual state and by the keyboard
/// handler to decide toggle-vs-switch.
bool isDestinationActive(ShellDestination dest, WidgetRef ref) {
  final overlay = ref.read(activeOverlayProvider);
  switch (dest) {
    case ShellDestination.vault:
      return overlay == ShellOverlay.vault;
    case ShellDestination.settings:
      return overlay == ShellOverlay.settings;
    case ShellDestination.connections:
      final tabs = ref.read(tabsControllerProvider);
      final showHome = !tabs.hasSessions || ref.read(homeRequestedProvider);
      return overlay == ShellOverlay.none && showHome;
    case ShellDestination.sftp:
      final tabs = ref.read(tabsControllerProvider);
      final showHome = !tabs.hasSessions || ref.read(homeRequestedProvider);
      return overlay == ShellOverlay.none &&
          !showHome &&
          tabs.activeTab?.kind == TabKind.sftp;
  }
}

/// Activate a rail destination (single shared path for the rail and the
/// ⌘/Ctrl+1..4 shortcuts; ADR 0030 D2/D7/D9).
///
/// - Connections: a top "place". Re-activating the already-active Connections
///   toggles the panel collapsed/expanded; otherwise it switches to the
///   connection home and ENSURES the panel is visible.
/// - SFTP: focuses an existing SFTP session; with NONE open it does NOT spawn an
///   empty tab — it surfaces the Connections panel + an inline hint (D9b).
/// - Vault / Settings: overlay toggles (unchanged semantics).
void activateDestination(ShellDestination dest, WidgetRef ref) {
  final overlayNotifier = ref.read(activeOverlayProvider.notifier);
  final sidebar = ref.read(sidebarControllerProvider.notifier);

  switch (dest) {
    case ShellDestination.connections:
      final wasActive = isDestinationActive(ShellDestination.connections, ref);
      overlayNotifier.state = ShellOverlay.none;
      ref.read(homeRequestedProvider.notifier).state = true;
      if (wasActive) {
        // Re-tapping the active place toggles the panel (D2).
        sidebar.toggle();
      } else {
        sidebar.setCollapsed(false);
      }
    case ShellDestination.sftp:
      overlayNotifier.state = ShellOverlay.none;
      final tabs = ref.read(tabsControllerProvider);
      final hasSftp = tabs.tabs.values.any((t) => t.kind == TabKind.sftp);
      if (hasSftp) {
        ref.read(homeRequestedProvider.notifier).state = false;
        ref.read(tabsControllerProvider.notifier).openOrFocus(TabKind.sftp);
      } else {
        // No SFTP session: don't open an empty placeholder. Point the user at
        // the Connections panel with a brief inline hint (D9b).
        ref.read(homeRequestedProvider.notifier).state = true;
        sidebar.setCollapsed(false);
        ref.read(sidebarHintProvider.notifier).state =
            'SFTP için bir host seçin';
      }
    case ShellDestination.vault:
      overlayNotifier.state = ref.read(activeOverlayProvider) == ShellOverlay.vault
          ? ShellOverlay.none
          : ShellOverlay.vault;
    case ShellDestination.settings:
      overlayNotifier.state =
          ref.read(activeOverlayProvider) == ShellOverlay.settings
          ? ShellOverlay.none
          : ShellOverlay.settings;
  }
}
