import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/connection.dart';
import '../../services/ssh/terminal_session.dart';
import '../../theme/theme_controller.dart';
import '../settings/app_settings.dart';
import '../terminal/terminal_session_controller.dart';
import 'shell_metrics.dart';
import 'split_tree.dart';

/// The connection currently selected for the detail card. Set by the sidebar
/// (and by ConnectionsView itself) and watched by ConnectionsView.
final selectedConnectionProvider = StateProvider<Connection?>((ref) => null);

/// Monotonic counter bumped whenever a "new host" is requested (sidebar "+"
/// or the in-view button). ConnectionsView listens for changes and opens the
/// connect dialog. A counter is used so repeated requests always notify.
final newHostRequestProvider = StateProvider<int>((ref) => 0);

/// A "connect to this saved host" request bridged from the connection tree
/// (double-click / Enter / context-menu "Bağlan" — ADR 0035 D4) to the connect
/// orchestration that lives in ConnectionsView. The orchestration owns the SSH
/// service + tabs; the sidebar only emits intent. Wrapped with a monotonic [seq]
/// so connecting to the SAME host twice in a row still notifies a listener.
class ConnectRequest {
  final Connection connection;
  final int seq;
  const ConnectRequest(this.connection, this.seq);
}

final connectRequestProvider = StateProvider<ConnectRequest?>((ref) => null);

/// Folder ids whose subtree is expanded in the sidebar tree.
final expandedFoldersProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Current sidebar search query (empty = no filter). Wired into the sidebar in
/// a later task; declared here so the provider exists.
final sidebarSearchProvider = StateProvider<String>((ref) => '');

/// Whether the vault is unlocked for this session. false = show the unlock
/// screen, true = show the app shell. Lifted out of the root widget's local
/// state so the Settings danger-zone reset can re-lock the session from deep in
/// the tree (set it back to false after a successful SecureStore.reset()).
final sessionUnlockedProvider = StateProvider<bool>((ref) => false);

/// The id of the tab currently being dragged (null when no drag is in flight).
/// Set by the tab pill on drag start/end so [AppShell] can reveal the per-group
/// "drop here to split" overlays only while a drag is active (ADR 0019).
final draggingTabProvider = StateProvider<String?>((ref) => null);

/// Persisted state of the connection sidebar (ADR 0021/0030): the chosen panel
/// [width] and whether it is [collapsed]. Both survive across sessions via the
/// same SharedPreferences mechanism the theme picker uses (ADR 0030 D4).
class SidebarState {
  /// Chosen panel width, clamped to the resizable range when applied.
  final double width;

  /// Whether the panel is collapsed (rail-only). Inverse of "visible".
  final bool collapsed;

  const SidebarState({required this.width, required this.collapsed});

  SidebarState copyWith({double? width, bool? collapsed}) => SidebarState(
    width: width ?? this.width,
    collapsed: collapsed ?? this.collapsed,
  );
}

/// Holds the persisted [SidebarState] (panel width + collapsed flag) and writes
/// changes back to SharedPreferences — reusing the theme picker's persistence
/// pattern (`sharedPrefsProvider`-backed Notifier; ADR 0030 D4/C2). Tolerates a
/// missing/overridden prefs provider (bare test containers) by falling back to
/// in-memory defaults so widget tests need not always seed prefs.
final sidebarControllerProvider =
    NotifierProvider<SidebarController, SidebarState>(SidebarController.new);

class SidebarController extends Notifier<SidebarState> {
  static const String _widthKey = 'sidebarWidth';
  static const String _collapsedKey = 'sidebarCollapsed';

  SharedPreferences? _prefs;

  @override
  SidebarState build() {
    try {
      _prefs = ref.read(sharedPrefsProvider);
    } catch (_) {
      _prefs = null; // bare container (e.g. some widget tests): in-memory only.
    }
    final savedWidth = _prefs?.getDouble(_widthKey);
    final savedCollapsed = _prefs?.getBool(_collapsedKey);
    return SidebarState(
      width: ShellMetrics.clampSidebarWidth(
        savedWidth ?? ShellMetrics.sidebarDefaultWidth,
      ),
      collapsed: savedCollapsed ?? false,
    );
  }

  /// Apply a freshly-dragged width: clamps to the range and persists it. If the
  /// raw drag falls below the collapse-snap threshold the panel collapses
  /// instead, leaving the previously persisted width untouched so re-expanding
  /// restores the last usable size. Hysteresis: snapping only happens on the way
  /// down (collapse), never auto-expanding, so the boundary does not flicker
  /// (ADR 0030 D4).
  void setWidth(double raw) {
    if (raw < ShellMetrics.sidebarCollapseSnap) {
      setCollapsed(true);
      return;
    }
    final w = ShellMetrics.clampSidebarWidth(raw);
    state = state.copyWith(width: w, collapsed: false);
    _prefs?.setDouble(_widthKey, w);
    _prefs?.setBool(_collapsedKey, false);
  }

  /// Persist the collapsed flag (true = rail-only, false = panel visible).
  void setCollapsed(bool collapsed) {
    state = state.copyWith(collapsed: collapsed);
    _prefs?.setBool(_collapsedKey, collapsed);
  }

  /// Toggle visibility (⌘B / rail toggle / re-tapping the active place).
  void toggle() => setCollapsed(!state.collapsed);
}

/// Whether the connection sidebar panel is shown (ADR 0021/0030). Derived from
/// the persisted [sidebarControllerProvider] so existing call-sites that watch
/// visibility keep working; writes go through [SidebarController].
final sidebarVisibleProvider = Provider<bool>(
  (ref) => !ref.watch(sidebarControllerProvider).collapsed,
);

/// The persisted, clamped sidebar panel width (ADR 0030 D4). Watched by
/// [AppShell] to size the panel and the resize drag handle.
final sidebarWidthProvider = Provider<double>(
  (ref) => ref.watch(sidebarControllerProvider).width,
);

/// A transient one-shot hint surfaced at the top of the Connections panel
/// (e.g. "SFTP için bir host seçin" when SFTP is requested with no session —
/// ADR 0030 D9b). Null = no hint. Cleared when the user interacts with the tree
/// or dismisses it.
final sidebarHintProvider = StateProvider<String?>((ref) => null);

/// Whether the connection "home" (welcome) surface is requested over the session
/// workspace (ADR 0022). The workspace shows the welcome whenever there are no
/// sessions OR this flag is set (e.g. the nav rail "Bağlantılar" item, or a
/// sidebar host selection, while sessions are open). It is cleared again when a
/// session is opened or focused so interacting with sessions returns to them.
/// Both surfaces stay mounted (outer IndexedStack), so sessions remain live.
final homeRequestedProvider = StateProvider<bool>((ref) => false);

/// The kinds of tab the strip can hold (ADR 0022): sessions only. Management
/// surfaces (Connections / Vault / Settings) are no longer tabs — Connections is
/// the sidebar + welcome, Vault & Settings are in-app overlays.
enum TabKind { terminal, sftp }

String _titleForKind(TabKind k) => switch (k) {
  TabKind.terminal => 'Terminal',
  TabKind.sftp => 'SFTP',
};

/// Derive an informative default title for an SFTP tab (ADR 0036 D3): include
/// host context ("SFTP · host") so SFTP panes are never the bare repeating
/// 'SFTP'. Falls back to the generic label when no host is known.
String _sftpTitle(String? host) {
  final h = host?.trim();
  return (h == null || h.isEmpty) ? _titleForKind(TabKind.sftp) : 'SFTP · $h';
}

/// Immutable identity of a tab. Live session state lives in
/// [TerminalSessionController], owned by [TabsController] — not here.
class ShellTab {
  final String id;
  final TabKind kind;

  /// The derived default title (connection name / host context, ADR 0036 D3).
  /// Stable for the life of the tab; [customTitle] overrides it for display.
  final String title;

  /// A user-set title from inline/menu rename (ADR 0036 D2). When non-null it
  /// is shown instead of [title]. Sticky: a future live OSC title (pass-2) must
  /// not overwrite a manual rename (title-lock priority manual > OSC > derived).
  final String? customTitle;

  /// Whether the user has pinned this tab. Pinned tabs render compact at the
  /// front of the strip and are protected from "close others/all" (ADR 0018).
  final bool pinned;

  const ShellTab({
    required this.id,
    required this.kind,
    required this.title,
    this.customTitle,
    this.pinned = false,
  });

  /// The title to display: a manual rename takes precedence over the derived
  /// default (ADR 0036 D2/D3).
  String get effectiveTitle => customTitle ?? title;

  ShellTab copyWith({
    String? title,
    bool? pinned,
    String? customTitle,
    bool clearCustomTitle = false,
  }) => ShellTab(
    id: id,
    kind: kind,
    title: title ?? this.title,
    customTitle: clearCustomTitle ? null : (customTitle ?? this.customTitle),
    pinned: pinned ?? this.pinned,
  );
}

/// Payload carried by a tab drag (UI → controller). Pure data.
class TabDragData {
  final String tabId;
  final String sourceGroupId;
  const TabDragData(this.tabId, this.sourceGroupId);
}

/// One editor group: ordered tab ids + the active one.
class TabGroup {
  final String id;
  final List<String> tabIds;
  final String? activeTabId;
  const TabGroup({required this.id, required this.tabIds, this.activeTabId});

  TabGroup copyWith({
    List<String>? tabIds,
    String? activeTabId,
    bool clearActive = false,
  }) => TabGroup(
    id: id,
    tabIds: tabIds ?? this.tabIds,
    activeTabId: clearActive ? null : (activeTabId ?? this.activeTabId),
  );
}

class TabsState {
  final Map<String, ShellTab> tabs;

  /// The editor groups, kept in DFS-leaf order of [layout] (left→right /
  /// top→bottom reading order). Membership is the source of truth; [layout]
  /// only describes how the groups are arranged on screen.
  final List<TabGroup> groups;
  final String activeGroupId;

  /// The split layout tree (ADR 0019). Invariant: `layout.groupIds ==
  /// groups.ids`.
  final SplitNode layout;

  const TabsState({
    required this.tabs,
    required this.groups,
    required this.activeGroupId,
    required this.layout,
  });

  TabsState copyWith({
    Map<String, ShellTab>? tabs,
    List<TabGroup>? groups,
    String? activeGroupId,
    SplitNode? layout,
  }) => TabsState(
    tabs: tabs ?? this.tabs,
    groups: groups ?? this.groups,
    activeGroupId: activeGroupId ?? this.activeGroupId,
    layout: layout ?? this.layout,
  );

  TabGroup get activeGroup => groups.firstWhere(
    (g) => g.id == activeGroupId,
    orElse: () => groups.first,
  );

  ShellTab? get activeTab {
    final id = activeGroup.activeTabId;
    return id == null ? null : tabs[id];
  }

  /// Whether any session tab is open. When false the workspace shows the
  /// connection "home" / welcome surface instead of the strip (ADR 0022).
  bool get hasSessions => tabs.isNotEmpty;
}

/// A record of a recently-closed tab so it can be reopened (Cmd/Ctrl+Shift+T).
/// Terminal tabs carry a [reopen] thunk that replays the full connect flow
/// (host-key dialog included) so reopening a terminal stays secure (ADR 0018);
/// SFTP (the only thunk-less session tab) reopens via [TabsController.openOrFocus].
class _ClosedTab {
  final TabKind kind;
  final String title;
  final void Function()? reopen;
  _ClosedTab({required this.kind, required this.title, this.reopen});
}

/// A tab that has been detached into a separate OS window (ADR 0020). Its
/// [TerminalSessionController] stays alive in [TabsController._terminals] (the
/// session lives in the main isolate; the window only renders via a proxy) while
/// it is hidden from the in-window layout. [redockTab] restores it.
class _DetachedTab {
  final ShellTab tab;
  final void Function()? reopen;
  _DetachedTab(this.tab, this.reopen);
}

final tabsControllerProvider = NotifierProvider<TabsController, TabsState>(
  TabsController.new,
);

/// The title of the active session (active group → active tab `effectiveTitle`,
/// ADR 0036), or null on the home / no-session surface (ADR 0039 D1). Watched by
/// the title bar to render the centered active-session title and to mirror it
/// into the OS window title. Pure derivation from [tabsControllerProvider], so
/// it is unit-tested without pumping the bar.
final activeSessionTitleProvider = Provider<String?>((ref) {
  final state = ref.watch(tabsControllerProvider);
  if (!state.hasSessions) return null;
  final title = state.activeTab?.effectiveTitle.trim();
  return (title == null || title.isEmpty) ? null : title;
});

/// The OS window title for a given active-session [title] (ADR 0039 D1):
/// 'sshall — <session>' when a session is active, plain 'sshall' on home. Pure
/// → unit-tested and reused by the title bar's `setTitle` mirror.
String osWindowTitleFor(String? title) =>
    (title == null || title.trim().isEmpty) ? 'sshall' : 'sshall — $title';

class TabsController extends Notifier<TabsState> {
  static const String _firstGroupId = 'g0';

  final Map<String, TerminalSessionController> _terminals = {};

  /// Reopen thunks for terminal tabs, keyed by tab id. Captured at
  /// [openTerminal] time and moved onto [_closedStack] when the tab closes.
  final Map<String, void Function()> _reopenThunks = {};

  /// LIFO stack of recently-closed tabs (capped) for reopen.
  final List<_ClosedTab> _closedStack = [];
  static const int _closedStackCap = 20;

  /// Tabs currently detached into a separate OS window (ADR 0020), keyed by tab
  /// id. Their sessions stay live in [_terminals] until re-docked or closed.
  final Map<String, _DetachedTab> _detached = {};

  /// Most-recently-used tab order (front = most recent) for Ctrl+Tab cycling.
  final List<String> _mru = [];
  bool _cycling = false;
  int _cycleIdx = 0;

  int _seq = 0;
  int _gSeq = 1; // 0 is reserved for the initial group id.

  /// The empty workspace: no session tabs, a single empty group (ADR 0022). The
  /// shell renders the connection "home" / welcome surface while this holds.
  TabsState _initial() => const TabsState(
    tabs: {},
    groups: [TabGroup(id: _firstGroupId, tabIds: [], activeTabId: null)],
    activeGroupId: _firstGroupId,
    layout: GroupLeaf(_firstGroupId),
  );

  @override
  TabsState build() {
    _seq = 0;
    _gSeq = 1;
    _mru.clear();
    _closedStack.clear();
    _reopenThunks.clear();
    _detached.clear();
    _cycling = false;
    _cycleIdx = 0;
    return _initial();
  }

  TerminalSessionController? controllerFor(String tabId) => _terminals[tabId];

  /// Whether [tabId] is a LIVE session (connected/authenticating terminal) for
  /// the confirm-before-close gate (ADR 0038 D7). SFTP tabs and already-closed
  /// or errored terminals are not treated as live (closing them prompts nothing).
  bool isLiveSession(String tabId) {
    final tc = _terminals[tabId];
    if (tc == null) return false;
    final s = tc.status.value;
    return s.isConnecting || s.isConnected;
  }

  /// All live terminal controllers (open + detached sessions), in no particular
  /// order. Used by the live host-status lookup (ADR 0032 D6) to map a
  /// connection's `host:port` to its current [SessionStatus].
  Iterable<TerminalSessionController> get liveControllers => _terminals.values;

  /// Whether there is at least one closed tab that can be reopened.
  bool get canReopenClosed => _closedStack.isNotEmpty;

  // --- queries ---
  TabGroup? _groupOf(String tabId) {
    for (final g in state.groups) {
      if (g.tabIds.contains(tabId)) return g;
    }
    return null;
  }

  TabGroup? _groupById(String id) =>
      state.groups.where((g) => g.id == id).firstOrNull;

  String? _neighbor(
    List<String> oldIds,
    String removed,
    List<String> remaining,
  ) {
    if (remaining.isEmpty) return null;
    final i = oldIds.indexOf(removed);
    for (var j = i; j < oldIds.length; j++) {
      if (oldIds[j] != removed && remaining.contains(oldIds[j])) {
        return oldIds[j];
      }
    }
    for (var j = i; j >= 0; j--) {
      if (oldIds[j] != removed && remaining.contains(oldIds[j])) {
        return oldIds[j];
      }
    }
    return remaining.first;
  }

  TabsState _normalize(
    Map<String, ShellTab> tabs,
    List<TabGroup> groups,
    String preferredActiveGroup,
    SplitNode layout,
  ) {
    var gs = groups.where((g) => g.tabIds.isNotEmpty).toList();
    if (gs.isEmpty) {
      final ids = tabs.keys.toList();
      return TabsState(
        tabs: tabs,
        groups: [
          TabGroup(
            id: _firstGroupId,
            tabIds: ids,
            activeTabId: ids.isEmpty ? null : ids.first,
          ),
        ],
        activeGroupId: _firstGroupId,
        layout: const GroupLeaf(_firstGroupId),
      );
    }
    gs = gs.map((g) {
      if (g.activeTabId != null && g.tabIds.contains(g.activeTabId)) return g;
      return g.copyWith(activeTabId: g.tabIds.first);
    }).toList();

    // Reconcile the layout tree to the surviving group set.
    final gsIds = gs.map((g) => g.id).toSet();
    var lay = layout;
    for (final id in layout.groupIds.difference(gsIds)) {
      lay = removeLeaf(lay, id);
    }
    // Safety net: ensure every surviving group is somewhere in the tree.
    for (final id in gsIds.difference(lay.groupIds)) {
      lay = (lay is GroupLeaf)
          ? SplitBranch(
              SplitAxis.horizontal,
              [lay, GroupLeaf(id)],
              const [0.5, 0.5],
            )
          : SplitBranch((lay as SplitBranch).axis, [
              ...lay.children,
              GroupLeaf(id),
            ], equalWeights(lay.children.length + 1));
    }

    // Order groups by DFS leaf order so groups[i] == the i-th panel on screen.
    final order = orderedLeafIds(lay);
    gs.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));

    final hasPreferred = gs.any((g) => g.id == preferredActiveGroup);
    return TabsState(
      tabs: tabs,
      groups: gs,
      activeGroupId: hasPreferred ? preferredActiveGroup : gs.first.id,
      layout: lay,
    );
  }

  // --- MRU helpers ---
  void _touchMru(String id) {
    _mru.remove(id);
    _mru.insert(0, id);
  }

  List<String> _mruValidOrder() {
    final present = _mru.where((id) => state.tabs.containsKey(id)).toList();
    for (final id in state.tabs.keys) {
      if (!present.contains(id)) present.add(id);
    }
    return present;
  }

  /// State-only activation (no MRU reorder, no cycling reset). Used by cycling.
  void _applyActive(String groupId, String tabId) {
    final groups = state.groups
        .map(
          (g) => (g.id == groupId && g.tabIds.contains(tabId))
              ? g.copyWith(activeTabId: tabId)
              : g,
        )
        .toList();
    state = state.copyWith(groups: groups, activeGroupId: groupId);
  }

  // --- open / focus ---
  String openTerminal(
    TerminalSession session,
    String title, {
    void Function()? reopen,
    String? hostPort,
    Future<void> Function()? reconnectThunk,
    void Function()? onEdit,
  }) {
    _cycling = false;
    final id = 't${_seq++}';
    // New tabs initialise their font size from the global default (ADR 0038 D5)
    // instead of the hard-coded kFontDefault. Read defensively so a bare test
    // container (no settings override) still opens tabs.
    double? initialFontSize;
    try {
      initialFontSize = ref
          .read(appSettingsControllerProvider)
          .terminalFontSize
          .toDouble();
    } catch (_) {
      initialFontSize = null;
    }
    _terminals[id] = TerminalSessionController(
      session,
      hostPort: hostPort,
      reconnectThunk: reconnectThunk,
      onEdit: onEdit,
      initialFontSize: initialFontSize,
    );
    if (reopen != null) _reopenThunks[id] = reopen;
    final newTabs = Map<String, ShellTab>.from(state.tabs)
      ..[id] = ShellTab(id: id, kind: TabKind.terminal, title: title);
    final groups = state.groups
        .map(
          (g) => g.id == state.activeGroupId
              ? g.copyWith(tabIds: [...g.tabIds, id], activeTabId: id)
              : g,
        )
        .toList();
    state = state.copyWith(tabs: newTabs, groups: groups);
    _touchMru(id);
    return id;
  }

  void openOrFocus(TabKind kind, {String? host}) {
    _cycling = false;
    for (final t in state.tabs.values) {
      if (t.kind == kind) {
        final g = _groupOf(t.id)!;
        setActive(g.id, t.id);
        return;
      }
    }
    final id = 's${_seq++}';
    // SFTP carries host context in its default title (ADR 0036 D3); other kinds
    // fall back to the plain kind label.
    final title = kind == TabKind.sftp ? _sftpTitle(host) : _titleForKind(kind);
    final newTabs = Map<String, ShellTab>.from(state.tabs)
      ..[id] = ShellTab(id: id, kind: kind, title: title);
    final groups = state.groups
        .map(
          (g) => g.id == state.activeGroupId
              ? g.copyWith(tabIds: [...g.tabIds, id], activeTabId: id)
              : g,
        )
        .toList();
    state = state.copyWith(tabs: newTabs, groups: groups);
    _touchMru(id);
  }

  void setActive(String groupId, String tabId) {
    _cycling = false;
    _applyActive(groupId, tabId);
    _touchMru(tabId);
  }

  void setActiveGroup(String groupId) {
    _cycling = false;
    final g = state.groups.where((g) => g.id == groupId).firstOrNull;
    if (g == null) return;
    state = state.copyWith(activeGroupId: groupId);
    if (g.activeTabId != null) _touchMru(g.activeTabId!);
  }

  void focusGroupByIndex(int index) {
    if (index < 0 || index >= state.groups.length) return;
    setActiveGroup(state.groups[index].id);
  }

  /// Cycle through tabs in MRU order (Ctrl+Tab / Ctrl+Shift+Tab). The cycle is
  /// committed (MRU reordered) on the next non-cycle interaction.
  void cycleMru(bool forward) {
    final order = _mruValidOrder();
    if (order.length < 2) return;
    if (!_cycling) {
      _cycling = true;
      _cycleIdx = 0;
    }
    _cycleIdx += forward ? 1 : -1;
    _cycleIdx %= order.length;
    if (_cycleIdx < 0) _cycleIdx += order.length;
    final id = order[_cycleIdx];
    final g = _groupOf(id);
    if (g != null) _applyActive(g.id, id);
  }

  /// Activate the next/previous tab within the active group, wrapping
  /// (Cmd/Ctrl+Shift+] / [).
  void activateRelativeInActiveGroup(int delta) {
    _cycling = false;
    final g = state.activeGroup;
    final ids = g.tabIds;
    if (ids.length < 2) return;
    final cur = g.activeTabId == null ? 0 : ids.indexOf(g.activeTabId!);
    var nxt = (cur + delta) % ids.length;
    if (nxt < 0) nxt += ids.length;
    setActive(g.id, ids[nxt]);
  }

  // --- close ---
  void _pushClosed(ShellTab tab) {
    final reopen = _reopenThunks.remove(tab.id);
    _closedStack.add(
      _ClosedTab(kind: tab.kind, title: tab.effectiveTitle, reopen: reopen),
    );
    if (_closedStack.length > _closedStackCap) _closedStack.removeAt(0);
  }

  void close(String tabId) {
    _cycling = false;
    final tab = state.tabs[tabId];
    if (tab == null) return;

    final tc = _terminals.remove(tabId);
    if (tc != null) unawaited(tc.dispose());
    _pushClosed(tab);
    _mru.remove(tabId);

    final newTabs = Map<String, ShellTab>.from(state.tabs)..remove(tabId);
    final newGroups = <TabGroup>[];
    for (final g in state.groups) {
      if (!g.tabIds.contains(tabId)) {
        newGroups.add(g);
        continue;
      }
      final ids = List<String>.from(g.tabIds)..remove(tabId);
      var active = g.activeTabId;
      if (active == tabId) active = _neighbor(g.tabIds, tabId, ids);
      newGroups.add(
        g.copyWith(
          tabIds: ids,
          activeTabId: active,
          clearActive: active == null,
        ),
      );
    }
    state = _normalize(newTabs, newGroups, state.activeGroupId, state.layout);
  }

  /// Close a batch of tabs at once, skipping pinned tabs. Disposes their terminal
  /// controllers and records them for reopen.
  void _closeMany(Iterable<String> ids) {
    final toClose = ids.where((id) {
      final t = state.tabs[id];
      return t != null && !t.pinned;
    }).toList();
    if (toClose.isEmpty) return;

    for (final id in toClose) {
      final tc = _terminals.remove(id);
      if (tc != null) unawaited(tc.dispose());
      _pushClosed(state.tabs[id]!);
      _mru.remove(id);
    }
    final closeSet = toClose.toSet();
    final newTabs = Map<String, ShellTab>.from(state.tabs)
      ..removeWhere((k, _) => closeSet.contains(k));
    final newGroups = state.groups.map((g) {
      final remaining = g.tabIds.where((id) => !closeSet.contains(id)).toList();
      var active = g.activeTabId;
      if (active != null && closeSet.contains(active)) {
        active = _neighbor(g.tabIds, active, remaining);
      }
      return g.copyWith(
        tabIds: remaining,
        activeTabId: active,
        clearActive: active == null,
      );
    }).toList();
    state = _normalize(newTabs, newGroups, state.activeGroupId, state.layout);
  }

  /// Close every closable, non-pinned tab in [tabId]'s group except [tabId].
  void closeOthers(String tabId) {
    _cycling = false;
    final g = _groupOf(tabId);
    if (g == null) return;
    _closeMany(g.tabIds.where((id) => id != tabId));
  }

  /// Close every closable, non-pinned tab to the right of [tabId] in its group.
  void closeToRight(String tabId) {
    _cycling = false;
    final g = _groupOf(tabId);
    if (g == null) return;
    final i = g.tabIds.indexOf(tabId);
    if (i < 0) return;
    _closeMany(g.tabIds.sublist(i + 1));
  }

  /// Close every closable, non-pinned tab in [groupId].
  void closeAllInGroup(String groupId) {
    _cycling = false;
    final g = state.groups.where((g) => g.id == groupId).firstOrNull;
    if (g == null) return;
    _closeMany(List<String>.from(g.tabIds));
  }

  /// Reopen the most-recently closed tab (Cmd/Ctrl+Shift+T).
  void reopenClosed() {
    _cycling = false;
    if (_closedStack.isEmpty) return;
    final ct = _closedStack.removeLast();
    if (ct.reopen != null) {
      ct.reopen!();
      return;
    }
    openOrFocus(ct.kind);
  }

  // --- rename ---

  /// Set a manual title for [tabId] (ADR 0036 D2). A blank/whitespace-only
  /// [title] clears the custom title so the tab falls back to its derived
  /// default ([ShellTab.title]). No-op for an unknown tab.
  void setTabTitle(String tabId, String title) {
    final tab = state.tabs[tabId];
    if (tab == null) return;
    final trimmed = title.trim();
    final newTab = trimmed.isEmpty
        ? tab.copyWith(clearCustomTitle: true)
        : tab.copyWith(customTitle: trimmed);
    state = state.copyWith(
      tabs: Map<String, ShellTab>.from(state.tabs)..[tabId] = newTab,
    );
  }

  // --- pin ---
  void togglePin(String tabId) {
    _cycling = false;
    final tab = state.tabs[tabId];
    if (tab == null) return;
    final newTab = tab.copyWith(pinned: !tab.pinned);
    final newTabs = Map<String, ShellTab>.from(state.tabs)..[tabId] = newTab;
    final src = _groupOf(tabId)!;
    final ids = List<String>.from(src.tabIds)..remove(tabId);
    // Pin → end of pinned region; unpin → start of unpinned region. Both land at
    // the pinned-count boundary (computed without this tab present).
    final boundary = ids.where((id) => newTabs[id]?.pinned ?? false).length;
    ids.insert(boundary.clamp(0, ids.length), tabId);
    final groups = state.groups
        .map((g) => g.id == src.id ? g.copyWith(tabIds: ids) : g)
        .toList();
    state = state.copyWith(tabs: newTabs, groups: groups);
  }

  // --- move / split ---

  /// Move [tabId] to [targetGroupId] at [insertIndex]. This is the single path
  /// for in-group reordering AND cross-group moves (drag-and-drop).
  ///
  /// [insertIndex] is a slot in the CURRENTLY RENDERED order of the target strip
  /// (for an in-group move, the dragged tab is still counted; this method
  /// adjusts). The index is clamped to the tab's pinned partition so an unpinned
  /// tab can never jump ahead of pinned tabs (and vice versa).
  void moveTab(String tabId, String targetGroupId, int insertIndex) {
    _cycling = false;
    final tab = state.tabs[tabId];
    if (tab == null) return;
    final src = _groupOf(tabId);
    if (src == null) return;
    if (!state.groups.any((g) => g.id == targetGroupId)) return;

    final sameGroup = src.id == targetGroupId;
    final fromIdx = src.tabIds.indexOf(tabId);

    final groups = state.groups.toList();
    final srcPos = groups.indexWhere((g) => g.id == src.id);

    final srcIds = List<String>.from(src.tabIds)..remove(tabId);
    final srcActive = src.activeTabId == tabId
        ? _neighbor(src.tabIds, tabId, srcIds)
        : src.activeTabId;
    groups[srcPos] = src.copyWith(
      tabIds: srcIds,
      activeTabId: srcActive,
      clearActive: srcActive == null,
    );

    final dstPos = groups.indexWhere((g) => g.id == targetGroupId);
    final dst = groups[dstPos];
    final dstIds = List<String>.from(dst.tabIds); // tab already removed if same

    var idx = insertIndex;
    if (sameGroup && fromIdx >= 0 && fromIdx < insertIndex) idx -= 1;

    final pinnedCount = dstIds
        .where((id) => state.tabs[id]?.pinned ?? false)
        .length;
    if (tab.pinned) {
      idx = idx.clamp(0, pinnedCount);
    } else {
      idx = idx.clamp(pinnedCount, dstIds.length);
    }
    dstIds.insert(idx, tabId);
    groups[dstPos] = dst.copyWith(tabIds: dstIds, activeTabId: tabId);

    state = _normalize(Map.of(state.tabs), groups, targetGroupId, state.layout);
    _touchMru(tabId);
  }

  /// Split [tabId] out of its group into a NEW group placed adjacent to
  /// [targetGroupId] in the direction [zone] (left/right → horizontal,
  /// top/bottom → vertical). [DropZone.center] moves the tab into the target
  /// group instead of splitting. The single path for body drop-to-split.
  void splitTabToGroup(String tabId, String targetGroupId, DropZone zone) {
    _cycling = false;
    final tab = state.tabs[tabId];
    if (tab == null) return;
    final src = _groupOf(tabId);
    if (src == null) return;
    final target = _groupById(targetGroupId);
    if (target == null) return;

    if (zone == DropZone.center) {
      moveTab(tabId, targetGroupId, target.tabIds.length);
      return;
    }
    // Splitting a single-tab group against itself would just vanish the panel.
    if (src.id == targetGroupId && src.tabIds.length < 2) return;

    final newGroupId = 'g${_gSeq++}';
    final srcIds = List<String>.from(src.tabIds)..remove(tabId);
    final srcActive = src.activeTabId == tabId
        ? _neighbor(src.tabIds, tabId, srcIds)
        : src.activeTabId;
    final groups = state.groups
        .map(
          (g) => g.id == src.id
              ? g.copyWith(
                  tabIds: srcIds,
                  activeTabId: srcActive,
                  clearActive: srcActive == null,
                )
              : g,
        )
        .toList();
    groups.add(TabGroup(id: newGroupId, tabIds: [tabId], activeTabId: tabId));
    final layout = insertLeaf(state.layout, targetGroupId, newGroupId, zone);
    state = _normalize(Map.of(state.tabs), groups, newGroupId, layout);
    _touchMru(tabId);
  }

  /// Split the active (or given) tab into a new group to the right of its
  /// current group. No-op for a single-tab group (nothing to separate).
  void splitRight([String? tabId]) {
    _cycling = false;
    final id = tabId ?? state.activeGroup.activeTabId;
    if (id == null) return;
    final src = _groupOf(id);
    if (src == null || src.tabIds.length < 2) return;
    splitTabToGroup(id, src.id, DropZone.right);
  }

  /// Move [tabId] to the next group (cyclic, DFS order). With a single group,
  /// splits it to the right (provided the source has >1 tab).
  void moveToOtherGroup(String tabId) {
    _cycling = false;
    if (state.tabs[tabId] == null) return;
    final src = _groupOf(tabId);
    if (src == null) return;
    if (state.groups.length < 2) {
      if (src.tabIds.length < 2) return;
      splitTabToGroup(tabId, src.id, DropZone.right);
      return;
    }
    final order = state.groups.map((g) => g.id).toList();
    final srcIdx = order.indexOf(src.id);
    final dstId = order[(srcIdx + 1) % order.length];
    final dst = _groupById(dstId)!;
    moveTab(tabId, dstId, dst.tabIds.length);
  }

  /// Update the weights of the split branch addressed by [path] (resize).
  void setLayoutWeights(List<int> path, List<double> weights) {
    state = state.copyWith(
      layout: updateWeightsAt(state.layout, path, weights),
    );
  }

  void unsplit() {
    if (state.groups.length < 2) return;
    final order = state.groups.map((g) => g.id).toList();
    final firstId = order.first;
    final first = _groupById(firstId)!;
    final ids = <String>[...first.tabIds];
    for (final gid in order.skip(1)) {
      ids.addAll(_groupById(gid)!.tabIds);
    }
    final merged = TabGroup(
      id: firstId,
      tabIds: ids,
      activeTabId: first.activeTabId ?? (ids.isEmpty ? null : ids.first),
    );
    state = _normalize(
      Map.of(state.tabs),
      [merged],
      firstId,
      GroupLeaf(firstId),
    );
  }

  Future<void> closeAll() async {
    final controllers = _terminals.values.toList();
    _terminals.clear();
    for (final tc in controllers) {
      await tc.dispose().catchError((_) {});
    }
    _reopenThunks.clear();
    _closedStack.clear();
    _detached.clear();
    _mru.clear();
    _seq = 0;
    _gSeq = 1;
    _cycling = false;
    _cycleIdx = 0;
    state = _initial();
  }

  // --- detach / redock to a separate OS window (ADR 0020) ---

  /// Whether [tabId] is currently shown in a detached window.
  bool isDetached(String tabId) => _detached.containsKey(tabId);

  /// Ids of all tabs currently detached into separate windows.
  Iterable<String> get detachedTabIds => _detached.keys;

  /// Detach [tabId] into a separate OS window: hide it from the in-window layout
  /// but keep its [TerminalSessionController] alive (the session stays in the
  /// main isolate and is rendered remotely via a proxy). No-op for an
  /// already-detached tab. The caller is responsible for opening the OS window
  /// and wiring the proxy (only terminal tabs are offered detach — ADR 0020/0022).
  void detachTab(String tabId) {
    _cycling = false;
    final tab = state.tabs[tabId];
    if (tab == null) return;
    if (_detached.containsKey(tabId)) return;

    _detached[tabId] = _DetachedTab(tab, _reopenThunks.remove(tabId));
    _mru.remove(tabId);

    // Remove from the visible layout WITHOUT disposing the controller.
    final newTabs = Map<String, ShellTab>.from(state.tabs)..remove(tabId);
    final newGroups = <TabGroup>[];
    for (final g in state.groups) {
      if (!g.tabIds.contains(tabId)) {
        newGroups.add(g);
        continue;
      }
      final ids = List<String>.from(g.tabIds)..remove(tabId);
      var active = g.activeTabId;
      if (active == tabId) active = _neighbor(g.tabIds, tabId, ids);
      newGroups.add(
        g.copyWith(
          tabIds: ids,
          activeTabId: active,
          clearActive: active == null,
        ),
      );
    }
    state = _normalize(newTabs, newGroups, state.activeGroupId, state.layout);
  }

  /// Re-dock a detached tab back into the main window (into [targetGroupId] or
  /// the active group), reusing its still-live session.
  ///
  /// The redocked tab is GUARANTEED to land in a real group that is present in
  /// the layout tree: pick [targetGroupId] if it exists, else the active group,
  /// else any surviving group, else a brand-new group. The result is run through
  /// [_normalize] so the tab can never end up in `tabs` without a rendered group
  /// (the "detached tab vanished after re-dock" class of bug). The window-side
  /// channel lifecycle is handled separately in [WindowDetachService].
  void redockTab(String tabId, [String? targetGroupId]) {
    _cycling = false;
    final d = _detached.remove(tabId);
    if (d == null) return;
    if (d.reopen != null) _reopenThunks[tabId] = d.reopen!;

    final newTabs = Map<String, ShellTab>.from(state.tabs)..[tabId] = d.tab;

    // Choose a destination group that actually exists.
    String? destId;
    if (targetGroupId != null && _groupById(targetGroupId) != null) {
      destId = targetGroupId;
    } else if (_groupById(state.activeGroupId) != null) {
      destId = state.activeGroupId;
    } else if (state.groups.isNotEmpty) {
      destId = state.groups.first.id;
    }

    // No usable group at all (all groups collapsed away): rebuild a clean
    // single-group layout around the redocked tab so it always renders.
    if (destId == null) {
      final newGroupId = 'g${_gSeq++}';
      state = _normalize(
        newTabs,
        [
          TabGroup(id: newGroupId, tabIds: [tabId], activeTabId: tabId),
        ],
        newGroupId,
        GroupLeaf(newGroupId),
      );
      _touchMru(tabId);
      return;
    }

    final dest = destId;
    final groups = state.groups
        .map(
          (g) => g.id == dest
              ? g.copyWith(tabIds: [...g.tabIds, tabId], activeTabId: tabId)
              : g,
        )
        .toList();
    // Normalize keeps groups/layout in sync (and grafts the dest group into the
    // tree via its safety net if it was ever missing).
    state = _normalize(newTabs, groups, dest, state.layout);
    _touchMru(tabId);
  }

  /// Dispose a detached tab's session (the window was closed without re-docking
  /// and the user chose not to keep the session).
  Future<void> disposeDetached(String tabId) async {
    _detached.remove(tabId);
    _reopenThunks.remove(tabId);
    final tc = _terminals.remove(tabId);
    if (tc != null) await tc.dispose().catchError((_) {});
  }
}
