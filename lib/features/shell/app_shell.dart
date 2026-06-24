import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/context_ext.dart';
import '../connections/connections_view.dart';
import '../settings/app_settings.dart';
import '../settings/settings_view.dart';
import '../sftp/sftp_view.dart';
import '../terminal/terminal_view.dart';
import '../vault/vault_view.dart';
import 'connection_sidebar.dart';
import 'close_tab_confirm.dart';
import 'nav_rail.dart';
import 'resizable_split.dart';
import 'shell_metrics.dart';
import 'shell_overlay.dart';
import 'shell_shortcuts.dart';
import 'shell_state.dart';
import 'split_tree.dart';
import 'tab_context_menu.dart';
import 'tab_group_view.dart';
import 'tab_rename_dialog.dart';
import 'title_bar.dart';
import 'window_chrome.dart';
import 'window_detach_service.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Stable widget identity per group so a group's subtree (terminal scrollback,
  /// strip scroll position, subscriptions) survives layout restructuring when
  /// the split tree changes (ADR 0019).
  final Map<String, GlobalKey> _groupKeys = {};

  GlobalKey _keyForGroup(String id) =>
      _groupKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    // Let the detach service reach the live controller (ADR 0020). Binding only
    // stores a reference; no platform channels are touched here.
    WindowDetachService.instance.bind(
      ref.read(tabsControllerProvider.notifier),
    );
    // A detached window inherits the live global terminal font (ADR 0038 D5).
    WindowDetachService.instance.bindFont(() {
      final s = ref.read(appSettingsControllerProvider);
      return (s.terminalFontSize.toDouble(), s.terminalFontFamily);
    });
    // Open-on-launch preference (ADR 0038 D7). 'welcome' forces the connection
    // home/welcome surface on first mount; 'last' leaves the workspace as-is
    // (deep session restore is pass-2). A real, persisted, observable wire.
    // Deferred to a post-frame callback so it never modifies a provider while
    // the first build is in flight (Riverpod forbids that).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(appSettingsControllerProvider).openOnLaunch ==
          OpenOnLaunch.welcome) {
        ref.read(homeRequestedProvider.notifier).state = true;
      }
    });
    // Mirror the active session into the OS window title (ADR 0039 D1) so
    // Mission Control / the window switcher show 'sshall — <session>' (or plain
    // 'sshall' on home). `listenManual` with `fireImmediately` also sets the
    // initial title; the derived provider only changes when the active session
    // (or its title) changes, so window_manager is touched no more than needed.
    ref.listenManual<String?>(activeSessionTitleProvider, (prev, next) {
      ref.read(windowChromeProvider).setTitle(osWindowTitleFor(next));
    }, fireImmediately: true);
  }

  Widget _contentFor(ShellTab tab) {
    switch (tab.kind) {
      case TabKind.sftp:
        return const SftpView();
      case TabKind.terminal:
        final ctrl = ref
            .read(tabsControllerProvider.notifier)
            .controllerFor(tab.id);
        if (ctrl == null) return const SizedBox.shrink();
        return TerminalView(controller: ctrl);
    }
  }

  void _handleAction(TabAction action, String tabId) {
    final n = ref.read(tabsControllerProvider.notifier);
    switch (action) {
      case TabAction.rename:
        // The pill's double-click inline editor is the primary path; this menu
        // entry opens a small dialog so rename also works for pinned/icon-only
        // tabs (no inline title) — ADR 0036 D2. Both end at setTabTitle.
        unawaited(_promptRename(tabId));
      case TabAction.unsplit:
        n.unsplit();
      case TabAction.close:
        // Confirm before closing a live session when the setting is on (D7).
        unawaited(closeTabWithConfirm(context, ref, tabId));
      case TabAction.closeOthers:
        n.closeOthers(tabId);
      case TabAction.closeToRight:
        n.closeToRight(tabId);
      case TabAction.closeAll:
        final g = ref
            .read(tabsControllerProvider)
            .groups
            .where((g) => g.tabIds.contains(tabId))
            .firstOrNull;
        if (g != null) n.closeAllInGroup(g.id);
      case TabAction.pin:
      case TabAction.unpin:
        n.togglePin(tabId);
      case TabAction.splitRight:
        n.splitRight(tabId);
      case TabAction.moveToOtherGroup:
        n.moveToOtherGroup(tabId);
      case TabAction.detachToWindow:
        final title =
            ref.read(tabsControllerProvider).tabs[tabId]?.effectiveTitle ?? '';
        WindowDetachService.instance.detachToWindow(tabId, title);
      case TabAction.reopenClosed:
        n.reopenClosed();
      case TabAction.reconnect:
        // Manual reconnect re-runs connect on the SAME tab (ADR 0032 D5).
        unawaited(n.controllerFor(tabId)?.reconnect() ?? Future.value());
    }
  }

  /// Menu-driven rename (ADR 0036 D2): a small dialog prefilled with the tab's
  /// current display title. Confirming writes via setTabTitle (an empty value
  /// clears back to the derived default). Works for pinned/icon-only tabs that
  /// have no inline title to double-click.
  Future<void> _promptRename(String tabId) async {
    final tab = ref.read(tabsControllerProvider).tabs[tabId];
    if (tab == null) return;
    final result = await showTabRenameDialog(context, tab.effectiveTitle);
    if (result == null || !mounted) return;
    ref.read(tabsControllerProvider.notifier).setTabTitle(tabId, result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tabsState = ref.watch(tabsControllerProvider);
    final notifier = ref.read(tabsControllerProvider.notifier);
    final isDragging = ref.watch(draggingTabProvider) != null;
    final sidebarVisible = ref.watch(sidebarVisibleProvider);
    final sidebarWidth = ref.watch(sidebarWidthProvider);
    final overlay = ref.watch(activeOverlayProvider);
    // The connection "home" / welcome shows whenever there are no sessions, or
    // the user explicitly asked for it (nav rail / sidebar) while sessions are
    // open (ADR 0022). Both surfaces stay mounted so sessions remain live.
    final showHome = !tabsState.hasSessions || ref.watch(homeRequestedProvider);

    // Drop keys for groups that no longer exist.
    final live = tabsState.groups.map((g) => g.id).toSet();
    _groupKeys.removeWhere((k, _) => !live.contains(k));

    Widget groupView(TabGroup g) => TabGroupView(
      group: g,
      tabs: tabsState.tabs,
      isActiveGroup: g.id == tabsState.activeGroupId,
      canReopen: notifier.canReopenClosed,
      statusFor: (id) => notifier.controllerFor(id)?.status,
      canReconnectFor: (id) =>
          notifier.controllerFor(id)?.canReconnect ?? false,
      contentBuilder: _contentFor,
      onSelect: (id) {
        ref.read(homeRequestedProvider.notifier).state = false;
        notifier.setActive(g.id, id);
      },
      onAction: _handleAction,
      onRenameTab: (id, title) => notifier.setTabTitle(id, title),
      // The strip "+" opens the SAME new-session launcher as double-tap-empty
      // (home/welcome). It never silently creates a blank session or persists
      // anything (ADR 0036 D1).
      onNewTab: () => ref.read(homeRequestedProvider.notifier).state = true,
      // The strip split button mirrors ⌘\ for this group's active tab (D6).
      onSplitRight: () {
        ref.read(homeRequestedProvider.notifier).state = false;
        notifier.setActiveGroup(g.id);
        notifier.splitRight();
      },
      // "Birleştir" (merge) is reachable while a split exists (D6).
      canMerge: tabsState.groups.length >= 2,
      onDrop: (data, targetGroup, index) =>
          notifier.moveTab(data.tabId, targetGroup, index),
      onDragStart: (id) => ref.read(draggingTabProvider.notifier).state = id,
      onDragEnd: () => ref.read(draggingTabProvider.notifier).state = null,
      // Double-clicking empty strip space surfaces the connection home/welcome
      // (the launcher for a new session) — ADR 0022.
      onDoubleTapEmpty: () =>
          ref.read(homeRequestedProvider.notifier).state = true,
      onActivateGroup: () {
        ref.read(homeRequestedProvider.notifier).state = false;
        notifier.setActiveGroup(g.id);
      },
      isDragging: isDragging,
      onBodyDrop: (data, zone) =>
          notifier.splitTabToGroup(data.tabId, g.id, zone),
      canDetach: WindowDetachService.supported,
    );

    // Recursively realize the split tree: leaves → keyed group views, branches
    // → resizable Row/Column whose handles write weights back to the controller.
    Widget node(SplitNode n, List<int> path) {
      if (n is GroupLeaf) {
        final g = tabsState.groups.where((x) => x.id == n.groupId).firstOrNull;
        if (g == null) return const SizedBox.shrink();
        return KeyedSubtree(key: _keyForGroup(g.id), child: groupView(g));
      }
      final b = n as SplitBranch;
      return ResizableSplit(
        axis: b.axis == SplitAxis.horizontal ? Axis.horizontal : Axis.vertical,
        weights: b.weights,
        onWeights: (w) => notifier.setLayoutWeights(path, w),
        children: [
          for (var i = 0; i < b.children.length; i++)
            node(b.children[i], [...path, i]),
        ],
      );
    }

    return Scaffold(
      backgroundColor: c.surface,
      body: ShellShortcuts(
        child: Column(
          children: [
            const TitleBar(),
            Expanded(
              child: Row(
                children: [
                  const NavRail(),
                  // Sidebar is collapsible (ADR 0021/0030) so a narrow window can
                  // hand the full width to content; toggled from the rail or ⌘B.
                  // Its width is persisted (ADR 0030 D4) and resized by dragging
                  // the right edge.
                  if (sidebarVisible) ...[
                    SizedBox(
                      width: sidebarWidth,
                      child: ConnectionSidebar(
                        // Selecting a host brings the connection home forward
                        // (its detail card lives there) without disturbing live
                        // sessions underneath (ADR 0022).
                        onSelect: (conn) {
                          ref.read(selectedConnectionProvider.notifier).state =
                              conn;
                          ref.read(homeRequestedProvider.notifier).state = true;
                        },
                        // Double-click / Enter / context-menu "Bağlan" on a host
                        // (ADR 0035 D4): emit a connect request that
                        // ConnectionsView's orchestration picks up.
                        onConnect: (conn) {
                          final prev =
                              ref.read(connectRequestProvider)?.seq ?? 0;
                          ref.read(connectRequestProvider.notifier).state =
                              ConnectRequest(conn, prev + 1);
                        },
                        onNewHost: () {
                          ref.read(homeRequestedProvider.notifier).state = true;
                          ref.read(newHostRequestProvider.notifier).state++;
                        },
                      ),
                    ),
                    _SidebarResizeHandle(startWidth: sidebarWidth),
                  ],
                  Expanded(
                    child: Container(
                      color: c.surface,
                      // Workspace stack: the home (welcome) surface and the
                      // session workspace are BOTH kept mounted in an
                      // IndexedStack so ConnectionsView's connect orchestration
                      // and terminal scrollback both stay live; the active
                      // overlay (Settings/Vault) rides on top (ADR 0022).
                      child: Stack(
                        children: [
                          IndexedStack(
                            index: showHome ? 0 : 1,
                            children: [
                              const ConnectionsView(),
                              node(tabsState.layout, const []),
                            ],
                          ),
                          if (overlay == ShellOverlay.settings)
                            const OverlayPanel(
                              icon: Icons.settings_outlined,
                              title: 'Ayarlar',
                              child: SettingsView(),
                            ),
                          if (overlay == ShellOverlay.vault)
                            const OverlayPanel(
                              icon: Icons.vpn_key_outlined,
                              title: 'Vault — Anahtar & Kimlik',
                              child: VaultView(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The invisible right-edge resize zone for the connection sidebar (ADR 0030
/// D4). A thin hit area showing [SystemMouseCursors.resizeLeftRight] on hover;
/// dragging writes the new (clamped, persisted) width through
/// [SidebarController], and dragging below the snap threshold collapses the
/// panel (with hysteresis so the boundary does not flicker).
class _SidebarResizeHandle extends ConsumerStatefulWidget {
  const _SidebarResizeHandle({required this.startWidth});

  /// The current panel width, captured as the drag's starting point.
  final double startWidth;

  @override
  ConsumerState<_SidebarResizeHandle> createState() =>
      _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends ConsumerState<_SidebarResizeHandle> {
  double _dragWidth = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: const Key('sidebarResizeHandle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragWidth = widget.startWidth,
        onHorizontalDragUpdate: (d) {
          _dragWidth += d.delta.dx;
          ref.read(sidebarControllerProvider.notifier).setWidth(_dragWidth);
        },
        child: SizedBox(
          width: ShellMetrics.sidebarResizeHandleWidth,
          // A 1px hairline keeps the panel/content seam crisp; the rest of the
          // zone is transparent but still a drag target.
          child: Center(child: Container(width: 1, color: c.border)),
        ),
      ),
    );
  }
}
