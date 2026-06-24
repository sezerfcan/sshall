import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/folders/connection_ops.dart';
import '../../data/folders/folder_ops.dart';
import '../../data/folders/tree.dart';
import '../../data/models/connection.dart';
import '../../data/models/folder.dart';
import '../../data/resolve/connection_resolver.dart';
import '../../theme/context_ext.dart';
import '../connections/host_status_provider.dart';
import '../terminal/session_status.dart';
import '../terminal/status_colors.dart';
import '../docker/containers_node.dart';
import '../docker/docker_actions.dart';
import '../docker/docker_providers.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/section_label.dart';
import 'connection_actions.dart';
import 'connection_move_target.dart';
import 'folder_actions.dart';
import 'folder_defaults_dialog.dart';
import 'match_highlight.dart';
import 'shell_metrics.dart';
import 'shell_overlay.dart';
import 'sidebar_drag.dart';
import 'sidebar_empty_states.dart';
import 'sidebar_row.dart';
import 'shell_state.dart';

class ConnectionSidebar extends ConsumerStatefulWidget {
  final void Function(Connection) onSelect;

  /// Double-click / Enter / context-menu "Bağlan" on a host (ADR 0035 D4). A
  /// pure add over [onSelect]; null leaves connect-from-tree unbound.
  final void Function(Connection)? onConnect;
  final VoidCallback onNewHost;

  const ConnectionSidebar({
    super.key,
    required this.onSelect,
    required this.onNewHost,
    this.onConnect,
  });

  @override
  ConsumerState<ConnectionSidebar> createState() => _ConnectionSidebarState();
}

class _ConnectionSidebarState extends ConsumerState<ConnectionSidebar> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _listKey = GlobalKey();
  Timer? _autoScrollTicker;

  /// Snapshot of the user's expanded folders taken when a search begins, so the
  /// set can be RESTORED when the query is cleared (ADR 0035 D3) — the search's
  /// force-expand must not permanently mutate the user's tree state.
  Set<String>? _preSearchExpanded;

  @override
  void dispose() {
    _autoScrollTicker?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Clears the search field AND the provider, then restores the pre-search
  /// expanded set (D3). Shared by the clear (x) button and the no-results CTA.
  void _clearSearch() {
    _searchController.clear();
    ref.read(sidebarSearchProvider.notifier).state = '';
    final restore = _preSearchExpanded;
    if (restore != null) {
      ref.read(expandedFoldersProvider.notifier).state = restore;
      _preSearchExpanded = null;
    }
  }

  void _onSearchChanged(String v) {
    final wasSearching = ref.read(sidebarSearchProvider).trim().isNotEmpty;
    final nowSearching = v.trim().isNotEmpty;
    // Snapshot the expanded set exactly once, on the transition into searching.
    if (!wasSearching && nowSearching) {
      _preSearchExpanded = ref.read(expandedFoldersProvider).toSet();
    } else if (wasSearching && !nowSearching) {
      // Cleared by typing rather than the x: restore too.
      final restore = _preSearchExpanded;
      if (restore != null) {
        ref.read(expandedFoldersProvider.notifier).state = restore;
        _preSearchExpanded = null;
      }
    }
    ref.read(sidebarSearchProvider.notifier).state = v;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final storeAsync = ref.watch(secureStoreProvider);
    return Container(
      decoration: BoxDecoration(color: c.bg),
      child: storeAsync.when(
        loading: () => const SizedBox(),
        error: (e, _) => Center(
          child: Text('$e', style: context.ui(color: c.red)),
        ),
        data: (store) => ListenableBuilder(
          listenable: store.revision,
          builder: (context, _) {
            final data = store.snapshot().valueOrNull;
            final folders = data?.folders ?? const <Folder>[];
            final conns = data?.connections ?? const <Connection>[];
            final pins = data?.pins.length ?? 0;
            final expanded = ref.watch(expandedFoldersProvider);
            final query = ref.watch(sidebarSearchProvider);
            final searching = query.trim().isNotEmpty;
            final filtered = filterTree(folders, conns, query);
            // When searching, force-expand kept folders so matches are visible.
            final effExpanded = searching
                ? filtered.folders.map((f) => f.id).toSet()
                : expanded;
            final rows = buildTreeRows(
              filtered.folders,
              filtered.conns,
              effExpanded,
            );
            // First-run is "an empty tree" — no saved connections AND no
            // folders — independent of search. (A user with only empty folders
            // still sees the tree so they can drag hosts into them.)
            final firstRun = conns.isEmpty && folders.isEmpty;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
                  child: Row(
                    children: [
                      const SectionLabel('Bağlantılar'),
                      const Spacer(),
                      Tooltip(
                        message: 'Host veya klasör ekle',
                        child: PopupMenuButton<String>(
                          key: const Key('sidebar-add'),
                          tooltip: '',
                          padding: EdgeInsets.zero,
                          color: c.elevated,
                          icon: Icon(Icons.add, size: 18, color: c.textMuted),
                          onSelected: (v) {
                            switch (v) {
                              case 'host':
                                widget.onNewHost();
                              case 'folder':
                                createFolderFlow(context, ref, parentId: null);
                            }
                          },
                          itemBuilder: (_) => [
                            _menuItem('host', 'Yeni host', context),
                            _menuItem('folder', 'Yeni klasör', context),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Tooltip(
                    message: 'Ad, host, etiket veya kullanıcıya göre arar',
                    child: AppTextField(
                      controller: _searchController,
                      fieldKey: const Key('sidebarSearch'),
                      label: 'İsim, host veya etiket ara',
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: c.textDim,
                      ),
                      // The clear (x) shows ONLY while the query is non-empty; it
                      // clears the controller + provider AND restores the
                      // pre-search expanded set (ADR 0035 D3). A plain
                      // GestureDetector (not IconButton) so it doesn't create a
                      // nested semantics node inside AppTextField's MergeSemantics.
                      suffixIcon: searching
                          ? Tooltip(
                              message: 'Aramayı temizle',
                              child: GestureDetector(
                                key: const Key('sidebarSearchClear'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _clearSearch,
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Center(
                                    child: Icon(
                                      Icons.close,
                                      size: 15,
                                      color: c.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : null,
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
                _hintBanner(context, ref),
                _localDockerNode(context, ref),
                Expanded(
                  child: _treeBody(
                    context,
                    ref,
                    rows: rows,
                    folders: filtered.folders,
                    effExpanded: effExpanded,
                    searching: searching,
                    firstRun: firstRun,
                    query: query,
                  ),
                ),
                _vaultFooter(context, ref, pins),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The scrollable tree area OR one of the three distinct empty states
  /// (ADR 0035 D2).
  Widget _treeBody(
    BuildContext context,
    WidgetRef ref, {
    required List<TreeRow> rows,
    required List<Folder> folders,
    required Set<String> effExpanded,
    required bool searching,
    required bool firstRun,
    required String query,
  }) {
    // (a) First-run: zero saved connections.
    if (firstRun && !searching) {
      return FirstRunEmptyState(onNewHost: widget.onNewHost);
    }
    // (c) Search with no matches.
    if (searching && rows.isEmpty) {
      return NoSearchResultsState(query: query.trim(), onClear: _clearSearch);
    }
    // Otherwise: the tree. (Non-first-run with no rows is impossible here.)
    return ListView.builder(
      key: _listKey,
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: rows.length,
      itemBuilder: (context, i) => _row(
        context,
        ref,
        rows[i],
        folders,
        effExpanded,
        searching: searching,
        query: query,
      ),
    );
  }

  /// Edge auto-scroll during a drag (ADR 0035 D1): when the live pointer nears
  /// the top/bottom of the tree's viewport, scroll toward that edge on each
  /// frame. Driven by [SidebarRow.onDragUpdateGlobal] (start) / onDragEnded
  /// (stop). A manual ticker keeps this dependency-free of internal scrollable
  /// plumbing while still feeling like a native auto-scroll.
  static const double _autoScrollHotZone = 48;
  static const double _autoScrollMaxSpeed = 14; // px per frame at the edge.
  double _autoScrollDelta = 0;

  void _onDragMove(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final h = box.size.height;
    double delta = 0;
    if (local.dy < _autoScrollHotZone) {
      final t = (1 - (local.dy / _autoScrollHotZone)).clamp(0.0, 1.0);
      delta = -_autoScrollMaxSpeed * t;
    } else if (local.dy > h - _autoScrollHotZone) {
      final t = ((local.dy - (h - _autoScrollHotZone)) / _autoScrollHotZone)
          .clamp(0.0, 1.0);
      delta = _autoScrollMaxSpeed * t;
    }
    _autoScrollDelta = delta;
    // Nothing to scroll (e.g. a short list that fits the viewport): never start
    // the ticker. This also keeps widget-test pumpAndSettle from spinning on a
    // periodic timer that can't make progress.
    final canScroll =
        _scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0;
    if (delta != 0 && canScroll && _autoScrollTicker == null) {
      _autoScrollTicker = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scrollController.hasClients || _autoScrollDelta == 0) {
          _stopAutoScroll();
          return;
        }
        final pos = _scrollController.position;
        final next = (pos.pixels + _autoScrollDelta).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        if (next != pos.pixels) {
          pos.jumpTo(next);
        } else {
          // Hit an edge — stop so we don't spin uselessly.
          _stopAutoScroll();
        }
      });
    } else if (delta == 0) {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScrollTicker?.cancel();
    _autoScrollTicker = null;
    _autoScrollDelta = 0;
  }

  /// A one-shot inline hint surfaced at the top of the panel (ADR 0030 D9b),
  /// e.g. "SFTP için bir host seçin" when SFTP is requested with no live
  /// session. Dismissable; rendered as a soft accent strip so it reads as
  /// guidance, not an error (§9).
  Widget _hintBanner(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final hint = ref.watch(sidebarHintProvider);
    if (hint == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Container(
        key: const Key('sidebar-hint'),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(hint, style: context.ui(size: 11.5, color: c.text)),
            ),
            Tooltip(
              message: 'İpucunu kapat',
              child: GestureDetector(
                key: const Key('sidebar-hint-dismiss'),
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    ref.read(sidebarHintProvider.notifier).state = null,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: c.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The footer is an actionable Vault button (ADR 0030 D9a): tapping it opens
  /// the Vault overlay; the known-host count rides along as supporting text.
  Widget _vaultFooter(BuildContext context, WidgetRef ref, int pins) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SidebarRow(
        rowKey: const Key('sidebar-vault-footer'),
        semanticLabel: 'Vault — anahtar & kimlik panelini aç',
        onTap: () =>
            ref.read(activeOverlayProvider.notifier).state = ShellOverlay.vault,
        child: Tooltip(
          message: 'Vault — anahtar & kimlik panelini aç',
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 15, color: c.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vault açık',
                  style: context.ui(size: 11, color: c.textMuted),
                ),
              ),
              Text(
                '$pins bilinen host',
                style: context.mono(size: 10, color: c.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Always-visible "Local Docker" node, pinned between the search field and the
  /// scrollable connections tree so it never scrolls out of view. Surfaces this
  /// machine's containers via the generalized [ContainersNode] (ADR 0028/0029).
  Widget _localDockerNode(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final localOpen = ref.watch(localDockerExpandedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SidebarRow(
          rowKey: const Key('local-docker-node'),
          semanticLabel: 'Local Docker — bu makinedeki container\'lar',
          onTap: () =>
              ref.read(localDockerExpandedProvider.notifier).state = !localOpen,
          child: Row(
            children: [
              Icon(
                localOpen ? Icons.expand_more : Icons.chevron_right,
                size: ShellMetrics.rowIconSize,
                color: c.textDim,
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Bu makinedeki Docker',
                // Tokenized, tintable Docker glyph (ADR 0030 D8) — was 🐳 emoji.
                child: Icon(
                  Icons.directions_boat_filled_outlined,
                  size: 15,
                  color: c.cyan,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Local Docker',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.ui(size: 12.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (localOpen)
          ContainersNode(
            containers: ref.watch(localContainerListProvider),
            onRetry: () => ref.invalidate(localContainerListProvider),
            retryKeyId: 'local',
            indent: ShellMetrics.localContainerIndent,
            onOpenTerminal: (ct) =>
                unawaited(openLocalContainerTerminal(context, ref, ct)),
            onBrowse: (ct) =>
                unawaited(openLocalContainerFiles(context, ref, ct)),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    TreeRow row,
    List<Folder> folders,
    Set<String> expanded, {
    required bool searching,
    required String query,
  }) {
    final indent =
        ShellMetrics.sidebarBaseIndent +
        row.depth * ShellMetrics.sidebarIndentStep;
    // Reorder/move DnD is DISABLED while a search query is active: the visible
    // order is filtered/force-expanded, not canonical, so a reorder would
    // corrupt `order` (ADR 0035 D1).
    final dnd = !searching;
    if (row.isFolder) {
      return _folderRow(
        context,
        ref,
        row,
        folders,
        expanded,
        indent: indent,
        dnd: dnd,
        query: query,
      );
    }
    return _hostRow(
      context,
      ref,
      row,
      folders,
      indent: indent,
      dnd: dnd,
      searching: searching,
      query: query,
    );
  }

  Widget _folderRow(
    BuildContext context,
    WidgetRef ref,
    TreeRow row,
    List<Folder> folders,
    Set<String> expanded, {
    required double indent,
    required bool dnd,
    required String query,
  }) {
    final c = context.c;
    final f = row.folder!;
    final isOpen = expanded.contains(f.id);
    final hasChildren =
        folders.any((x) => x.parentId == f.id) ||
        ref
            .read(secureStoreProvider)
            .valueOrNull!
            .snapshot()
            .valueOrNull!
            .connections
            .any((cn) => cn.folderId == f.id);

    final folderRow = SidebarRow(
      rowKey: Key('folder-${f.id}'),
      indent: indent,
      isFolderRow: true,
      semanticLabel: '${f.name} klasörü',
      dragGhostLabel: f.name,
      dragGhostIcon: Icons.folder_outlined,
      dndEnabled: dnd,
      dragData: SidebarDragData(
        id: f.id,
        isFolder: true,
        sourceDepth: row.depth,
      ),
      onDragUpdateGlobal: _onDragMove,
      onDragEnded: _stopAutoScroll,
      // Reject dropping a folder into its own descendant (cycle).
      willAcceptDrag: (data, zone) {
        if (data.isFolder && zone == DropZone.into) {
          return !wouldCreateCycle(data.id, f.id, folders);
        }
        return true;
      },
      onDropBefore: (data) => _handleReorderDrop(
        ref,
        data,
        targetParentId: f.parentId,
        before: f,
        after: null,
      ),
      onDropAfter: (data) => _handleReorderDrop(
        ref,
        data,
        targetParentId: f.parentId,
        before: null,
        after: f,
      ),
      onDropInto: (data) => _handleIntoDrop(ref, data, folderId: f.id),
      onSecondaryTapDown: (d) =>
          _showFolderContextMenu(context, ref, f, d.globalPosition),
      onTap: () {
        final next = {...expanded};
        isOpen ? next.remove(f.id) : next.add(f.id);
        ref.read(expandedFoldersProvider.notifier).state = next;
      },
      revealedTrailing: _folderMenu(context, ref, f),
      child: Row(
        children: [
          Tooltip(
            message: 'Klasörü aç/kapat',
            child: Icon(
              isOpen ? Icons.expand_more : Icons.chevron_right,
              size: ShellMetrics.rowIconSize,
              color: c.textDim,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.folder_outlined, size: 14, color: c.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: _label(
              context,
              f.name,
              query,
              weight: FontWeight.w600,
              color: c.text,
            ),
          ),
        ],
      ),
    );

    // (b) Empty-folder inline hint (ADR 0035 D2): an expanded folder with no
    // children gets a muted, indented "drag a host here" line, woven directly
    // under its row. It also acts as a move-into drop target so a drag lands.
    if (isOpen && !hasChildren) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          folderRow,
          DragTarget<SidebarDragData>(
            onWillAcceptWithDetails: (d) =>
                !(d.data.isFolder &&
                    wouldCreateCycle(d.data.id, f.id, folders)),
            onAcceptWithDetails: (d) =>
                _handleIntoDrop(ref, d.data, folderId: f.id),
            builder: (context, _, __) => EmptyFolderHint(depth: row.depth),
          ),
        ],
      );
    }
    return folderRow;
  }

  Widget _hostRow(
    BuildContext context,
    WidgetRef ref,
    TreeRow row,
    List<Folder> folders, {
    required double indent,
    required bool dnd,
    required bool searching,
    required String query,
  }) {
    final c = context.c;
    final conn = row.connection!;
    final resolvedConn = resolve(conn, folders);
    final user = resolvedConn.username ?? '';
    final dockerOpen =
        conn.docker && ref.watch(expandedDockerProvider).contains(conn.id);
    // Reflect the selected connection in the tree (ADR 0030 D5 — #1 HIGH bug):
    // a selected host row gets a soft accent background + accent text.
    final selected = ref.watch(selectedConnectionProvider)?.id == conn.id;
    // Live session status lights the host-row dot (ADR 0032 D6): was a static
    // textDim. Idle hosts still read dim; an open session shows its real color.
    final liveStatus = ref.watch(
      hostStatusProvider,
    )['${conn.host}:${resolvedConn.port}'];
    final hostRow = SidebarRow(
      rowKey: Key('host-${conn.id}'),
      indent: indent + ShellMetrics.hostRowIndent,
      selected: selected,
      semanticLabel: conn.label,
      dragGhostLabel: conn.label,
      dragGhostIcon: Icons.dns_outlined,
      dndEnabled: dnd,
      dragData: SidebarDragData(
        id: conn.id,
        isFolder: false,
        sourceDepth: row.depth,
      ),
      onDragUpdateGlobal: _onDragMove,
      onDragEnded: _stopAutoScroll,
      onDropBefore: (data) => _handleHostReorderDrop(
        ref,
        data,
        targetFolderId: conn.folderId,
        before: conn,
        after: null,
      ),
      onDropAfter: (data) => _handleHostReorderDrop(
        ref,
        data,
        targetFolderId: conn.folderId,
        before: null,
        after: conn,
      ),
      onTap: () {
        // Interacting with the tree dismisses any one-shot hint (D9b).
        ref.read(sidebarHintProvider.notifier).state = null;
        widget.onSelect(conn);
      },
      // Double-click connects (ADR 0035 D4) — a pure add over single-click select.
      onDoubleTap: widget.onConnect == null
          ? null
          : () {
              ref.read(sidebarHintProvider.notifier).state = null;
              ref.read(selectedConnectionProvider.notifier).state = conn;
              widget.onConnect!(conn);
            },
      onSecondaryTapDown: (d) =>
          _showHostContextMenu(context, ref, conn, d.globalPosition),
      revealedTrailing: _hostMenu(context, ref, conn),
      child: Row(
        children: [
          Tooltip(
            message: liveStatus != null
                ? statusLabel(liveStatus)
                : 'Bağlı değil',
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: liveStatus != null
                    ? statusColorOf(liveStatus, c)
                    : (selected ? c.accent : c.textDim),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _label(
              context,
              conn.label,
              query,
              color: selected ? c.accent : c.text,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (conn.docker) ...[
            Tooltip(
              message: 'Docker host',
              // Tokenized, tintable Docker glyph (ADR 0030 D8) — was 🐳 emoji.
              child: Icon(
                Icons.directions_boat_filled_outlined,
                size: 14,
                color: c.cyan,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: "Container'ları aç/kapat",
              child: InkWell(
                key: Key('docker-toggle-${conn.id}'),
                onTap: () {
                  final next = {...ref.read(expandedDockerProvider)};
                  dockerOpen ? next.remove(conn.id) : next.add(conn.id);
                  ref.read(expandedDockerProvider.notifier).state = next;
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    dockerOpen ? Icons.expand_more : Icons.chevron_right,
                    size: ShellMetrics.rowIconSize,
                    color: c.textDim,
                  ),
                ),
              ),
            ),
          ],
          Text(user, style: context.mono(size: 10, color: c.textDim)),
        ],
      ),
    );
    if (!conn.docker) return hostRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        hostRow,
        if (dockerOpen)
          ContainersNode(
            containers: ref.watch(containerListProvider(conn.id)),
            onRetry: () => ref.invalidate(containerListProvider(conn.id)),
            retryKeyId: conn.id,
            indent: indent + ShellMetrics.containerRowIndent,
            onOpenTerminal: (ct) =>
                unawaited(openContainerTerminal(context, ref, conn, ct)),
            onBrowse: (ct) =>
                unawaited(openContainerFiles(context, ref, conn, ct)),
          ),
      ],
    );
  }

  /// Row label, accent-highlighting the matched substring while searching
  /// (ADR 0035 D3). Plain [Text] when not searching (zero overhead / unchanged).
  Widget _label(
    BuildContext context,
    String text,
    String query, {
    required FontWeight weight,
    required Color color,
  }) {
    final base = context.ui(size: 12.5, color: color, weight: weight);
    if (query.trim().isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final c = context.c;
    final hit = context.ui(
      size: 12.5,
      color: c.accent,
      weight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        children: highlightMatch(text, query, base: base, hit: hit),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ── Drop handlers (ADR 0035 D1) ───────────────────────────────────────────
  // Each routes the dragged payload to a pure op and persists in ONE atomic
  // store.mutate revision (no schema change — only order/folderId are written).

  /// A folder dropped before/after another folder at the same level (reorder),
  /// possibly re-parenting if it came from elsewhere.
  Future<void> _handleReorderDrop(
    WidgetRef ref,
    SidebarDragData data, {
    required String? targetParentId,
    required Folder? before,
    required Folder? after,
  }) async {
    if (!data.isFolder) {
      // A host dropped on a folder's edge lands in the folder's PARENT level
      // (root-level reorder context); move it there at the end.
      await _moveHostToFolder(ref, data.id, targetParentId);
      return;
    }
    final store = await ref.read(secureStoreProvider.future);
    await store.mutate((v) {
      final siblings =
          [
            for (final fo in v.folders)
              if (fo.id != data.id && fo.parentId == targetParentId) fo,
          ]..sort(
            (a, b) => a.order != b.order
                ? a.order.compareTo(b.order)
                : a.name.compareTo(b.name),
          );
      final anchor = before ?? after;
      var idx = siblings.indexWhere((s) => s.id == anchor?.id);
      if (idx < 0) idx = siblings.length;
      if (after != null) idx += 1;
      return moveFolderOrdered(
        v,
        data.id,
        newParentId: targetParentId,
        order: idx,
      );
    });
  }

  /// A node dropped INTO a folder (nest). Folder→folder uses moveFolderOrdered
  /// (cycle-guarded); host→folder uses moveConnection.
  Future<void> _handleIntoDrop(
    WidgetRef ref,
    SidebarDragData data, {
    required String folderId,
  }) async {
    if (data.isFolder) {
      final store = await ref.read(secureStoreProvider.future);
      await store.mutate((v) {
        final order = nextOrder(
          v.folders
              .where((f) => f.id != data.id && f.parentId == folderId)
              .map((f) => f.order),
        );
        return moveFolderOrdered(
          v,
          data.id,
          newParentId: folderId,
          order: order,
        );
      });
      return;
    }
    await _moveHostToFolder(ref, data.id, folderId);
  }

  /// A host dropped before/after another host (same-folder reorder, or a
  /// cross-folder move when the target host lives elsewhere).
  Future<void> _handleHostReorderDrop(
    WidgetRef ref,
    SidebarDragData data, {
    required String? targetFolderId,
    required Connection? before,
    required Connection? after,
  }) async {
    if (data.isFolder) return; // a folder can't nest under a host's edge.
    final store = await ref.read(secureStoreProvider.future);
    await store.mutate((v) {
      final siblings =
          [
            for (final cn in v.connections)
              if (cn.id != data.id && cn.folderId == targetFolderId) cn,
          ]..sort(
            (a, b) => a.order != b.order
                ? a.order.compareTo(b.order)
                : a.label.compareTo(b.label),
          );
      final anchor = before ?? after;
      var idx = siblings.indexWhere((s) => s.id == anchor?.id);
      if (idx < 0) idx = siblings.length;
      if (after != null) idx += 1;
      return moveConnection(v, data.id, folderId: targetFolderId, order: idx);
    });
  }

  Future<void> _moveHostToFolder(
    WidgetRef ref,
    String connId,
    String? folderId,
  ) async {
    final store = await ref.read(secureStoreProvider.future);
    await store.mutate((v) {
      final order = nextOrder(
        v.connections
            .where((c) => c.id != connId && c.folderId == folderId)
            .map((c) => c.order),
      );
      return moveConnection(v, connId, folderId: folderId, order: order);
    });
  }

  // ── Context menus (ADR 0035 D4) ───────────────────────────────────────────
  // Right-click mirrors the kebab exactly and SELECTS the row first.

  Future<void> _showHostContextMenu(
    BuildContext context,
    WidgetRef ref,
    Connection conn,
    Offset globalPosition,
  ) async {
    ref.read(sidebarHintProvider.notifier).state = null;
    widget.onSelect(conn); // select first (D4).
    final selected = await _showRowMenu<String>(context, globalPosition, [
      _popItem('connect', 'Bağlan', context),
      _popItem('edit', 'Düzenle', context),
      _popItem('move', 'Klasöre taşı…', context),
      _popItem('delete', 'Sil', context),
    ]);
    if (!context.mounted || selected == null) return;
    switch (selected) {
      case 'connect':
        widget.onConnect?.call(conn);
      case 'edit':
        editConnectionFlow(context, ref, conn);
      case 'move':
        moveConnectionToFolderFlow(context, ref, conn);
      case 'delete':
        deleteConnectionFlow(context, ref, conn);
    }
  }

  Future<void> _showFolderContextMenu(
    BuildContext context,
    WidgetRef ref,
    Folder f,
    Offset globalPosition,
  ) async {
    final selected = await _showRowMenu<String>(context, globalPosition, [
      _popItem('subfolder', 'Yeni alt klasör', context),
      _popItem('defaults', 'Varsayılanlar', context),
      _popItem('rename', 'Yeniden adlandır', context),
      _popItem('move', 'Taşı', context),
      _popItem('delete', 'Sil', context),
    ]);
    if (!context.mounted || selected == null) return;
    switch (selected) {
      case 'subfolder':
        createFolderFlow(context, ref, parentId: f.id);
      case 'defaults':
        showFolderDefaultsDialog(context, ref, folderId: f.id);
      case 'rename':
        renameFolderFlow(context, ref, f);
      case 'move':
        moveFolderFlow(context, ref, f);
      case 'delete':
        deleteFolderFlow(context, ref, f);
    }
  }

  /// Opens a context menu anchored at the global pointer position (right-click).
  Future<T?> _showRowMenu<T>(
    BuildContext context,
    Offset globalPosition,
    List<PopupMenuEntry<T>> items,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    return showMenu<T>(
      context: context,
      position: pos,
      color: context.c.elevated,
      items: items,
    );
  }

  Widget _hostMenu(BuildContext context, WidgetRef ref, Connection conn) {
    final c = context.c;
    return Tooltip(
      message: 'Bağlantı işlemleri',
      child: PopupMenuButton<String>(
        key: Key('host-menu-${conn.id}'),
        tooltip: '',
        padding: EdgeInsets.zero,
        color: c.elevated,
        icon: Icon(Icons.more_horiz, size: 16, color: c.textDim),
        onSelected: (v) {
          switch (v) {
            case 'connect':
              widget.onConnect?.call(conn);
            case 'edit':
              editConnectionFlow(context, ref, conn);
            case 'move':
              moveConnectionToFolderFlow(context, ref, conn);
            case 'delete':
              deleteConnectionFlow(context, ref, conn);
          }
        },
        itemBuilder: (_) => [
          if (widget.onConnect != null) _menuItem('connect', 'Bağlan', context),
          _menuItem('edit', 'Düzenle', context),
          _menuItem('move', 'Klasöre taşı…', context),
          _menuItem('delete', 'Sil', context),
        ],
      ),
    );
  }

  Widget _folderMenu(BuildContext context, WidgetRef ref, Folder f) {
    final c = context.c;
    return Tooltip(
      message: 'Klasör işlemleri',
      child: PopupMenuButton<String>(
        key: Key('folder-menu-${f.id}'),
        tooltip: '',
        padding: EdgeInsets.zero,
        color: c.elevated,
        icon: Icon(Icons.more_horiz, size: 16, color: c.textDim),
        onSelected: (v) {
          switch (v) {
            case 'subfolder':
              createFolderFlow(context, ref, parentId: f.id);
            case 'defaults':
              showFolderDefaultsDialog(context, ref, folderId: f.id);
            case 'rename':
              renameFolderFlow(context, ref, f);
            case 'move':
              moveFolderFlow(context, ref, f);
            case 'delete':
              deleteFolderFlow(context, ref, f);
          }
        },
        itemBuilder: (_) => [
          _menuItem('subfolder', 'Yeni alt klasör', context),
          _menuItem('defaults', 'Varsayılanlar', context),
          _menuItem('rename', 'Yeniden adlandır', context),
          _menuItem('move', 'Taşı', context),
          _menuItem('delete', 'Sil', context),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String label,
    BuildContext context,
  ) => PopupMenuItem<String>(
    value: value,
    height: 40,
    child: Text(label, style: context.ui(size: 13)),
  );

  PopupMenuItem<String> _popItem(
    String value,
    String label,
    BuildContext context,
  ) => PopupMenuItem<String>(
    value: value,
    height: 38,
    child: Text(label, style: context.ui(size: 13)),
  );
}
