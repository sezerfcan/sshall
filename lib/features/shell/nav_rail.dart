import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/context_ext.dart';
import 'rail_item.dart';
import 'shell_destinations.dart';
import 'shell_metrics.dart';
import 'shell_overlay.dart';
import 'shell_state.dart';

/// The left navigation rail (ADR 0022/0030). It is a FIXED-width mode switcher,
/// NOT a tab bar: it switches the panel/home content (Connections, SFTP) and
/// toggles the Settings/Vault overlays. Live session tabs live in the tab strip,
/// never here. The rail is the single source of truth for the active mode and
/// never resizes (ADR 0030 D1).
class NavRail extends ConsumerWidget {
  const NavRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // Watch the providers that drive the active visual state so the rail
    // repaints when the mode changes; isDestinationActive reads them via ref.
    ref.watch(tabsControllerProvider);
    ref.watch(activeOverlayProvider);
    ref.watch(homeRequestedProvider);
    final sidebarVisible = ref.watch(sidebarVisibleProvider);

    bool active(ShellDestination d) => isDestinationActive(d, ref);

    // Show / hide the connection sidebar (ADR 0021/0030). This is a CONTROL, not
    // a "place": it is visually separated from the destination items (placed
    // apart, no left accent bar). Discoverable via tooltip + the platform-aware
    // primary shortcut (⌘B on macOS, Ctrl+B elsewhere) (§9).
    final glyph = primaryModifierGlyph();
    final binding = glyph == '⌘' ? '${glyph}B' : '$glyph+B';
    final sidebarToggle = RailItem(
      key: const Key('sidebarToggle'),
      icon: sidebarVisible ? Icons.menu_open_outlined : Icons.menu_outlined,
      tooltip: sidebarVisible
          ? 'Kenar çubuğunu gizle ($binding)'
          : 'Kenar çubuğunu göster ($binding)',
      semanticLabel: 'Kenar çubuğunu göster/gizle',
      active: sidebarVisible,
      showActiveBar: false, // control, not a destination — no left bar.
      onTap: () => ref.read(sidebarControllerProvider.notifier).toggle(),
    );

    return Container(
      width: ShellMetrics.railWidth,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(right: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: ShellMetrics.railVerticalPadding,
      ),
      child: Column(
        children: [
          // The show/hide control sits apart from the destination cluster: a
          // small extra gap + a hairline divider separate the two.
          sidebarToggle,
          const SizedBox(height: ShellMetrics.railClusterGap),
          Container(
            width: ShellMetrics.railItemSize,
            height: 1,
            color: c.border,
          ),
          const SizedBox(height: ShellMetrics.railClusterGap),
          // Top cluster: the "places".
          RailItem(
            key: const Key('navConnections'),
            icon: Icons.dns_outlined,
            tooltip: railTooltip('Bağlantılar', 1),
            semanticLabel: 'Bağlantılar',
            active: active(ShellDestination.connections),
            onTap: () => activateDestination(ShellDestination.connections, ref),
          ),
          RailItem(
            key: const Key('navSftp'),
            icon: Icons.sync_alt,
            tooltip: railTooltip('SFTP', 2),
            semanticLabel: 'SFTP',
            active: active(ShellDestination.sftp),
            onTap: () => activateDestination(ShellDestination.sftp, ref),
          ),
          const Spacer(),
          // Hairline divider separating the bottom "tools" cluster from the
          // top cluster, in addition to the Spacer (ADR 0030 D3).
          Container(
            width: ShellMetrics.railItemSize,
            height: 1,
            color: c.border,
          ),
          const SizedBox(height: ShellMetrics.railClusterGap),
          // Bottom cluster: the overlay "tools".
          RailItem(
            key: const Key('navVault'),
            icon: Icons.vpn_key_outlined,
            tooltip: railTooltip('Vault', 3),
            semanticLabel: 'Vault',
            active: active(ShellDestination.vault),
            onTap: () => activateDestination(ShellDestination.vault, ref),
          ),
          RailItem(
            key: const Key('navSettings'),
            icon: Icons.settings_outlined,
            tooltip: railTooltip('Ayarlar', 4),
            semanticLabel: 'Ayarlar',
            active: active(ShellDestination.settings),
            onTap: () => activateDestination(ShellDestination.settings, ref),
          ),
        ],
      ),
    );
  }
}
