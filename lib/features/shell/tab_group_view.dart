import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../terminal/session_status.dart';
import 'group_body_drop_target.dart';
import 'shell_state.dart';
import 'shell_tab_bar.dart';
import 'split_tree.dart';
import 'tab_context_menu.dart';

/// One group: its tab strip on top, an IndexedStack of its tabs below.
/// The IndexedStack keeps every tab mounted (state preserved); only the active
/// index is painted. Content for each tab is produced by [contentBuilder] so
/// this widget stays decoupled from concrete views. While a tab drag is in
/// flight ([isDragging]) the body shows a five-zone drop overlay (ADR 0019).
class TabGroupView extends StatelessWidget {
  final TabGroup group;
  final Map<String, ShellTab> tabs;
  final bool isActiveGroup;
  final bool canReopen;
  final ValueListenable<SessionStatus>? Function(String) statusFor;
  final bool Function(String) canReconnectFor;
  final Widget Function(ShellTab) contentBuilder;
  final void Function(String) onSelect;
  final void Function(TabAction action, String tabId) onAction;

  /// Commit a manual tab title from the pill's inline rename (ADR 0036 D2).
  final void Function(String tabId, String newTitle) onRenameTab;

  /// Open the new-session launcher (home/welcome) from the strip "+" (ADR 0036
  /// D1) — same path as double-tap-empty; does NOT persist.
  final VoidCallback onNewTab;

  /// Split this group to the right from the strip split button (ADR 0036 D6).
  final VoidCallback onSplitRight;

  /// Whether a split exists (>=2 groups) so the "Birleştir" menu item is enabled.
  final bool canMerge;

  final void Function(TabDragData data, String targetGroupId, int insertIndex)
  onDrop;
  final void Function(String) onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDoubleTapEmpty;
  final VoidCallback onActivateGroup;

  /// True while any tab is being dragged anywhere in the shell.
  final bool isDragging;

  /// Whether tabs can be detached into a separate OS window (desktop only).
  final bool canDetach;

  /// Called when a tab is dropped on this group's body (directional split or,
  /// for [DropZone.center], a move into this group).
  final void Function(TabDragData data, DropZone zone) onBodyDrop;

  const TabGroupView({
    super.key,
    required this.group,
    required this.tabs,
    required this.isActiveGroup,
    required this.canReopen,
    required this.statusFor,
    required this.canReconnectFor,
    required this.contentBuilder,
    required this.onSelect,
    required this.onAction,
    required this.onRenameTab,
    required this.onNewTab,
    required this.onSplitRight,
    required this.canMerge,
    required this.onDrop,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDoubleTapEmpty,
    required this.onActivateGroup,
    required this.isDragging,
    required this.onBodyDrop,
    this.canDetach = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ids = group.tabIds.where((id) => tabs[id] != null).toList();
    final activeIndex = group.activeTabId == null
        ? 0
        : ids
              .indexOf(group.activeTabId!)
              .clamp(0, ids.isEmpty ? 0 : ids.length - 1);

    // Active split-pane body cue (ADR 0036 D5): an inset accent border around
    // the FOCUSED group's body (same accent as the active-tab strip), a neutral
    // 1px border when inactive. This is the primary "where does my input go"
    // signal; clicking an inactive pane focuses it and the border updates.
    final bodyBorder = Border.all(
      color: isActiveGroup ? c.accent : c.border,
      width: isActiveGroup ? 2 : 1,
    );

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTapDown: (_) {
        if (!isActiveGroup) onActivateGroup();
      },
      child: Column(
        children: [
          ShellTabBar(
            group: group,
            tabs: tabs,
            isActiveGroup: isActiveGroup,
            canReopen: canReopen,
            canDetach: canDetach,
            statusFor: statusFor,
            canReconnectFor: canReconnectFor,
            onSelect: onSelect,
            onAction: onAction,
            onRenameTab: onRenameTab,
            onNewTab: onNewTab,
            onSplitRight: onSplitRight,
            canSplit: group.tabIds.where((id) => tabs[id] != null).length >= 2,
            canMerge: canMerge,
            onDrop: onDrop,
            onDragStart: onDragStart,
            onDragEnd: onDragEnd,
            onDoubleTapEmpty: onDoubleTapEmpty,
          ),
          Expanded(
            child: Container(
              key: Key('groupBody_${group.id}'),
              decoration: BoxDecoration(border: bodyBorder),
              // The 5-zone drag overlay (GroupBodyDropTarget) lives INSIDE the
              // border so the border never hides the drop preview (ADR 0019).
              child: GroupBodyDropTarget(
                groupId: group.id,
                dragActive: isDragging,
                onDrop: onBodyDrop,
                child: ids.isEmpty
                    ? const SizedBox.shrink()
                    : IndexedStack(
                        index: activeIndex,
                        children: [
                          for (final id in ids) contentBuilder(tabs[id]!),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
