import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/remote_entry.dart';
import '../../theme/context_ext.dart';
import 'file_pane_skeleton.dart';
import 'fs_format.dart';
import 'path_breadcrumb.dart';

/// Sortable columns in a [FilePane] (D3). Permissions only applies to the remote
/// pane.
enum SortColumn { name, size, modified, permissions }

/// Returns [entries] sorted by [column]/[ascending] (D3). Pure + shared by the
/// pane (which renders the order) and the view (which maps a clicked row index
/// back to an entry for selection), so both always agree on the order.
///
/// For [SortColumn.name] directories still group before files (the previous
/// default). For the other columns directories also group first (they have no
/// meaningful size/permissions), then files sort by the column; nulls sink to
/// the end. Reversing only flips the within-group comparison, never the
/// dirs-first grouping (so toggling direction never scatters folders into the
/// files).
List<FsEntry> sortEntries(
  List<FsEntry> entries,
  SortColumn column,
  bool ascending,
) {
  final list = [...entries];
  int cmpName(FsEntry a, FsEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  int dir = ascending ? 1 : -1;
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1; // dirs first, always
    switch (column) {
      case SortColumn.name:
        return dir * cmpName(a, b);
      case SortColumn.size:
        final c = a.size.compareTo(b.size);
        return c != 0 ? dir * c : cmpName(a, b);
      case SortColumn.modified:
        final am = a.modified, bm = b.modified;
        if (am == null && bm == null) return cmpName(a, b);
        if (am == null) return 1; // nulls last
        if (bm == null) return -1;
        final c = am.compareTo(bm);
        return c != 0 ? dir * c : cmpName(a, b);
      case SortColumn.permissions:
        final ap = a.mode, bp = b.mode;
        if (ap == null && bp == null) return cmpName(a, b);
        if (ap == null) return 1;
        if (bp == null) return -1;
        final c = ap.compareTo(bp);
        return c != 0 ? dir * c : cmpName(a, b);
    }
  });
  return list;
}

class FilePaneActions {
  final void Function(FsEntry) onOpen;
  final void Function(FsEntry) onTransfer;
  final void Function(FsEntry) onRename;
  final void Function(FsEntry) onDelete;
  final VoidCallback onMkdir;

  /// Remote-only: null hides the chmod menu item (e.g. for the local pane).
  final void Function(FsEntry)? onChmod;

  /// Remote-only: edit a remote file in an external editor (D3). Null (local
  /// pane / dirs) hides the "Düzenle" item.
  final void Function(FsEntry)? onEdit;

  /// Copy the entry's full path to the clipboard (D4 overflow tail).
  final void Function(FsEntry)? onCopyPath;

  const FilePaneActions({
    required this.onOpen,
    required this.onTransfer,
    required this.onRename,
    required this.onDelete,
    required this.onMkdir,
    this.onChmod,
    this.onEdit,
    this.onCopyPath,
  });
}

/// In-app drag payload for cross-pane transfers (D5). Carries the dragged
/// selection and whether it originated on the remote pane (so the drop target
/// can derive upload vs download direction).
class FileDragData {
  final List<FsEntry> entries;
  final bool fromRemote;
  const FileDragData({required this.entries, required this.fromRemote});
}

class FilePane extends StatelessWidget {
  final String title;
  final String path;
  final List<FsEntry> entries;
  final bool loading;
  final String? error;
  final VoidCallback onUp;
  final VoidCallback onRefresh;
  final FilePaneActions actions;

  /// Navigate to an absolute path (breadcrumb segment click / raw edit, D2).
  final void Function(String absolutePath)? onNavigate;

  /// True for the remote pane: shows the permissions column, enables chmod/edit
  /// inline, and tags drag payloads as `fromRemote`.
  final bool isRemote;

  // ---- sort (D3) ----
  final SortColumn sortColumn;
  final bool sortAscending;
  final void Function(SortColumn) onSort;

  // ---- selection (D4) ----
  /// Names of currently-selected entries (stable across re-sorts).
  final Set<String> selectedNames;

  /// Single-click select. [index] is into the *sorted* list; modifiers come
  /// from the live keyboard. The view computes the resulting selection.
  final void Function(int index, {bool shift, bool meta})? onSelect;

  /// Double-click activate (open dir / transfer file).
  final void Function(FsEntry)? onActivate;

  /// Transfer the whole current selection to the other pane (inline primary
  /// action + context menu). Falls back to the single row when nothing or only
  /// this row is selected.
  final void Function(FsEntry)? onTransferSelection;

  /// Delete the whole current selection (context menu / overflow).
  final void Function(FsEntry)? onDeleteSelection;

  // ---- drag & drop (D5) ----
  /// A selection was dropped onto this pane (or a folder row in it). [targetDir]
  /// is the folder path when dropped on a folder row, else null = current dir.
  final void Function(FileDragData data, {String? targetDir})? onDropEntries;

  /// Local pane only (null on the remote pane): lets the user grant access to a
  /// folder via the OS picker (macOS App Sandbox — ADR 0023). When set, a
  /// "choose folder" button shows in the header and, on an access error, an
  /// inline "Klasör seç" action appears next to the message.
  final VoidCallback? onChooseRoot;

  const FilePane({
    super.key,
    required this.title,
    required this.path,
    required this.entries,
    required this.loading,
    required this.error,
    required this.onUp,
    required this.onRefresh,
    required this.actions,
    this.onNavigate,
    this.isRemote = false,
    this.sortColumn = SortColumn.name,
    this.sortAscending = true,
    required this.onSort,
    this.selectedNames = const {},
    this.onSelect,
    this.onActivate,
    this.onTransferSelection,
    this.onDeleteSelection,
    this.onDropEntries,
    this.onChooseRoot,
  });

  bool get showPermissions => isRemote;

  List<FsEntry> get _sorted => sortEntries(entries, sortColumn, sortAscending);

  // Fixed column widths (D3; drag-resize is pass-2).
  static const double _sizeColW = 80;
  static const double _dateColW = 140;
  static const double _permColW = 110;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sorted = _sorted;
    return DragTarget<FileDragData>(
      onWillAcceptWithDetails: (d) =>
          onDropEntries != null && d.data.fromRemote != isRemote,
      onAcceptWithDetails: (d) => onDropEntries?.call(d.data),
      builder: (context, candidate, rejected) {
        final dropping = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(
              color: dropping ? c.accent : c.border,
              width: dropping ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, c),
              Divider(height: 1, color: c.border),
              _columnHeaders(context, c),
              Divider(height: 1, color: c.border),
              if (error != null) _errorBar(context, c),
              Expanded(child: _body(context, c, sorted)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, dynamic c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      children: [
        Text(
          title,
          style: context.ui(
            size: 11,
            weight: FontWeight.w700,
            color: c.textDim,
            spacing: 0.6,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: onNavigate != null
              ? PathBreadcrumb(path: path, onNavigate: onNavigate!)
              : Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mono(size: 12, color: c.textMuted),
                ),
        ),
        Tooltip(
          message: 'Üst klasör',
          child: IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: onUp,
          ),
        ),
        if (onChooseRoot != null)
          Tooltip(
            message: 'Klasör seç / erişim ver',
            child: IconButton(
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: onChooseRoot,
            ),
          ),
        Tooltip(
          message: 'Yeni klasör',
          child: IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: actions.onMkdir,
          ),
        ),
        Tooltip(
          message: 'Yenile',
          child: IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
          ),
        ),
      ],
    ),
  );

  Widget _columnHeaders(BuildContext context, dynamic c) => Padding(
    padding: const EdgeInsets.only(left: 34, right: 10, top: 5, bottom: 5),
    child: LayoutBuilder(
      builder: (context, cons) {
        // The header row's inner width excludes the left/right padding (44px)
        // already applied; rows include the leading icon/name inside their own
        // padding, so add back a matching reserve estimate to stay aligned.
        final vis = visibleColumns(cons.maxWidth + 44 - 20, showPermissions);
        return Row(
          children: [
            Expanded(child: _colHeader(context, c, 'Ad', SortColumn.name)),
            if (vis.size)
              SizedBox(
                width: _sizeColW,
                child: _colHeader(
                  context,
                  c,
                  'Boyut',
                  SortColumn.size,
                  alignEnd: true,
                ),
              ),
            if (vis.modified)
              SizedBox(
                width: _dateColW,
                child: _colHeader(
                  context,
                  c,
                  'Değiştirilme',
                  SortColumn.modified,
                ),
              ),
            if (vis.permissions)
              SizedBox(
                width: _permColW,
                child: _colHeader(
                  context,
                  c,
                  'İzinler',
                  SortColumn.permissions,
                ),
              ),
            const SizedBox(width: 28), // overflow-menu gutter
          ],
        );
      },
    ),
  );

  Widget _colHeader(
    BuildContext context,
    dynamic c,
    String label,
    SortColumn col, {
    bool alignEnd = false,
  }) {
    final active = sortColumn == col;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.ui(
              size: 11,
              weight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? c.text : c.textDim,
            ),
          ),
        ),
        Icon(
          active
              ? (sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
              : Icons.unfold_more,
          size: 14,
          color: active ? c.accent : c.textDim.withValues(alpha: 0.5),
        ),
      ],
    );
    return Tooltip(
      message: '$label sütununa göre sırala',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: Key('sortHeader_${col.name}'),
        borderRadius: BorderRadius.circular(4),
        onTap: () => onSort(col),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: row,
        ),
      ),
    );
  }

  Widget _errorBar(BuildContext context, dynamic c) => Padding(
    padding: const EdgeInsets.all(10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          onChooseRoot != null ? Icons.lock_outline : Icons.error_outline,
          size: 14,
          color: c.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(error!, style: context.ui(size: 12, color: c.red)),
        ),
        const SizedBox(width: 8),
        if (onChooseRoot != null)
          TextButton.icon(
            onPressed: onChooseRoot,
            icon: const Icon(Icons.folder_open_outlined, size: 14),
            label: const Text('Klasör seç'),
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: context.ui(size: 12, weight: FontWeight.w600),
            ),
          )
        else
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Yenile'),
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: context.ui(size: 12, weight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );

  Widget _body(BuildContext context, dynamic c, List<FsEntry> sorted) {
    // (1) First load: skeleton placeholders (no whole-list spinner).
    if (loading && sorted.isEmpty) {
      return FilePaneSkeleton(showPermissions: showPermissions);
    }
    // (3) Empty.
    if (!loading && sorted.isEmpty && error == null) {
      return _emptyState(context, c);
    }
    final list = ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (ctx, i) => _row(ctx, sorted[i], i),
    );
    // (2) Refresh: keep the previous list visible but dimmed, with a thin top
    // progress bar so content never disappears.
    if (loading && sorted.isNotEmpty) {
      return Stack(
        children: [
          Opacity(opacity: 0.5, child: list),
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ],
      );
    }
    return list;
  }

  Widget _emptyState(BuildContext context, dynamic c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_off_outlined, size: 32, color: c.textDim),
        const SizedBox(height: 8),
        Text('Boş klasör', style: context.ui(size: 13, color: c.textMuted)),
        if (onChooseRoot != null) ...[
          const SizedBox(height: 6),
          Text(
            'Başka bir klasöre geçmek için "Klasör seç"i kullanabilirsin.',
            style: context.ui(size: 11, color: c.textDim),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    ),
  );

  /// Reads the live shift/meta modifier state for click selection (D4).
  ({bool shift, bool meta}) _modifiers() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final meta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    return (shift: shift, meta: meta);
  }

  Widget _row(BuildContext context, FsEntry e, int index) {
    final c = context.c;
    final selected = selectedNames.contains(e.name);
    final canEdit =
        isRemote && !e.isDir && !e.isSymlink && actions.onEdit != null;

    final rowInner = _RowContent(
      entry: e,
      selected: selected,
      showPermissions: showPermissions,
      isRemote: isRemote,
      canEdit: canEdit,
      sizeColW: _sizeColW,
      dateColW: _dateColW,
      permColW: _permColW,
      onTransfer: onTransferSelection ?? actions.onTransfer,
      onEdit: actions.onEdit,
      onMenuSelected: (v) => _onMenuAction(context, v, e),
      menuItems: _menuItems(e),
    );

    // Tap/double-tap via a timestamp-based detector (not GestureDetector's
    // onDoubleTap), so it never holds the gesture arena and the row's nested
    // action buttons / overflow menu stay instantly tappable (no 300ms delay).
    Widget interactive = _RowGesture(
      onTap: () {
        final m = _modifiers();
        if (onSelect != null) {
          onSelect!(index, shift: m.shift, meta: m.meta);
        } else {
          actions.onOpen(e); // legacy fallback
        }
      },
      onDoubleTap: () => (onActivate ?? actions.onOpen)(e),
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition, e, index),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : null,
          border: Border(
            left: BorderSide(
              color: selected ? c.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: rowInner,
      ),
    );

    // Each row is draggable (D5). If it is part of a multi-selection the payload
    // carries the whole selection; otherwise just this entry.
    if (onDropEntries != null || onTransferSelection != null) {
      final dragEntries = selected && selectedNames.length > 1
          ? _sorted.where((x) => selectedNames.contains(x.name)).toList()
          : <FsEntry>[e];
      interactive = Draggable<FileDragData>(
        data: FileDragData(entries: dragEntries, fromRemote: isRemote),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragChip(count: dragEntries.length, label: e.name),
        childWhenDragging: Opacity(opacity: 0.4, child: interactive),
        child: interactive,
      );
    }

    // Folder rows are also drop targets (drop INTO that folder, D5).
    if (e.isDir && onDropEntries != null) {
      return DragTarget<FileDragData>(
        onWillAcceptWithDetails: (d) => d.data.fromRemote != isRemote,
        onAcceptWithDetails: (d) =>
            onDropEntries?.call(d.data, targetDir: _entryPath(e)),
        builder: (context, candidate, rejected) {
          final over = candidate.isNotEmpty;
          return Container(
            decoration: over
                ? BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: interactive,
          );
        },
      );
    }
    return interactive;
  }

  String _entryPath(FsEntry e) =>
      e is RemoteEntry ? e.path : (e as dynamic).path as String;

  List<_MenuAction> _menuItems(FsEntry e) {
    final n = selectedNames.contains(e.name) && selectedNames.length > 1
        ? selectedNames.length
        : 1;
    final suffix = n > 1 ? ' ($n)' : '';
    return [
      const _MenuAction('open', 'Aç'),
      if (actions.onEdit != null && !e.isDir && !e.isSymlink)
        const _MenuAction('edit', 'Düzenle'),
      _MenuAction('transfer', 'Diğer panele aktar$suffix'),
      const _MenuAction('rename', 'Yeniden adlandır'),
      _MenuAction('delete', 'Sil$suffix'),
      if (actions.onChmod != null && !e.isSymlink)
        const _MenuAction('chmod', 'İzinler'),
      if (actions.onCopyPath != null)
        const _MenuAction('copyPath', 'Yolu kopyala'),
    ];
  }

  void _onMenuAction(BuildContext context, String v, FsEntry e) {
    switch (v) {
      case 'open':
        (onActivate ?? actions.onOpen)(e);
      case 'transfer':
        (onTransferSelection ?? actions.onTransfer)(e);
      case 'rename':
        actions.onRename(e);
      case 'delete':
        (onDeleteSelection ?? actions.onDelete)(e);
      case 'chmod':
        actions.onChmod?.call(e);
      case 'edit':
        actions.onEdit?.call(e);
      case 'copyPath':
        actions.onCopyPath?.call(e);
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPos,
    FsEntry e,
    int index,
  ) async {
    // Right-click selects the row first (unless it is already in a multi-sel).
    if (!selectedNames.contains(e.name)) {
      onSelect?.call(index, shift: false, meta: false);
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in _menuItems(e))
          PopupMenuItem(value: item.value, child: Text(item.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '_mkdir', child: Text('Yeni klasör')),
        const PopupMenuItem(value: '_refresh', child: Text('Yenile')),
      ],
    );
    if (selected == null || !context.mounted) return;
    if (selected == '_mkdir') {
      actions.onMkdir();
    } else if (selected == '_refresh') {
      onRefresh();
    } else {
      _onMenuAction(context, selected, e);
    }
  }
}

/// One pane row's content (icon + name + size/date/perms cells + inline actions
/// + overflow). Split out so the [Draggable]/[DragTarget] wrappers in
/// [FilePane._row] stay readable.
class _RowContent extends StatelessWidget {
  final FsEntry entry;
  final bool selected;
  final bool showPermissions;
  final bool isRemote;
  final bool canEdit;
  final double sizeColW, dateColW, permColW;
  final void Function(FsEntry) onTransfer;
  final void Function(FsEntry)? onEdit;
  final void Function(String) onMenuSelected;
  final List<_MenuAction> menuItems;

  const _RowContent({
    required this.entry,
    required this.selected,
    required this.showPermissions,
    required this.isRemote,
    required this.canEdit,
    required this.sizeColW,
    required this.dateColW,
    required this.permColW,
    required this.onTransfer,
    required this.onEdit,
    required this.onMenuSelected,
    required this.menuItems,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = entry;
    // Inline transfer direction: local pane uploads (→), remote downloads (←).
    final transferIcon = isRemote ? Icons.arrow_back : Icons.arrow_forward;
    final transferTip = isRemote ? 'Yerele aktar' : 'Uzağa aktar';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: LayoutBuilder(
        builder: (context, cons) {
          final vis = visibleColumns(cons.maxWidth, showPermissions);
          return Row(
            children: [
              Icon(
                e.isDir
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: 16,
                color: e.isDir ? c.accent : c.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.ui(size: 13, color: c.text),
                ),
              ),
              // Inline high-frequency verbs (transfer + edit). Always laid out so
              // they stay findable; visually they read as row affordances.
              Tooltip(
                message: transferTip,
                child: IconButton(
                  icon: Icon(transferIcon, size: 15, color: c.accent),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: () => onTransfer(e),
                ),
              ),
              if (canEdit)
                Tooltip(
                  message: 'Düzenle',
                  child: IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: c.textMuted,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: () => onEdit?.call(e),
                  ),
                ),
              if (vis.size)
                SizedBox(
                  width: sizeColW,
                  child: Text(
                    e.isDir ? '—' : humanSize(e.size),
                    textAlign: TextAlign.right,
                    style: context.mono(size: 11, color: c.textDim),
                  ),
                ),
              if (vis.modified)
                SizedBox(
                  width: dateColW,
                  child: Text(
                    humanDate(e.modified),
                    textAlign: TextAlign.right,
                    style: context.mono(size: 11, color: c.textDim),
                  ),
                ),
              if (vis.permissions)
                SizedBox(
                  width: permColW,
                  child: Text(
                    humanMode(e.mode),
                    textAlign: TextAlign.right,
                    style: context.mono(size: 11, color: c.textDim),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Eylemler',
                icon: Icon(Icons.more_horiz, size: 16, color: c.textDim),
                onSelected: onMenuSelected,
                itemBuilder: (ctx) => [
                  for (final item in menuItems)
                    PopupMenuItem(value: item.value, child: Text(item.label)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Which optional columns fit in [maxWidth] (D3 responsive defaults). Pure so
/// the column headers and the rows agree on what to show. Below the thresholds
/// the date and then the permission columns are dropped (the size column is
/// kept the longest as the most useful); the values stay reachable in the row's
/// own tooltip/menu either way.
({bool size, bool modified, bool permissions}) visibleColumns(
  double maxWidth,
  bool showPermissions,
) {
  // Budget reserved for icon + name + inline actions + overflow gutter.
  const reserved = 150.0;
  final budget = maxWidth - reserved;
  var size = false, modified = false, permissions = false;
  var used = 0.0;
  if (budget - used >= FilePane._sizeColW) {
    size = true;
    used += FilePane._sizeColW;
  }
  if (showPermissions && budget - used >= FilePane._permColW) {
    permissions = true;
    used += FilePane._permColW;
  }
  if (budget - used >= FilePane._dateColW) {
    modified = true;
    used += FilePane._dateColW;
  }
  return (size: size, modified: modified, permissions: permissions);
}

class _MenuAction {
  final String value;
  final String label;
  const _MenuAction(this.value, this.label);
}

/// Row tap handler that distinguishes single- vs double-tap WITHOUT entering the
/// gesture arena (D4). It listens to raw pointer-up events via a [Listener], so
/// the row's nested action buttons / overflow menu / drag recognizer keep their
/// own gesture arenas and stay instantly responsive (no 300ms double-tap delay,
/// no competing onTap that would swallow a menu button's tap).
///
/// A primary-button release fires [onTap] immediately; a second release within
/// [_doubleTapWindow] (close in space) fires [onDoubleTap]. A secondary-button
/// (right-click) press fires [onSecondaryTapDown]. Selection is idempotent, so
/// the leading single-tap before a double-tap is harmless.
class _RowGesture extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(TapDownDetails) onSecondaryTapDown;
  final Widget child;

  const _RowGesture({
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
    required this.child,
  });

  @override
  State<_RowGesture> createState() => _RowGestureState();
}

class _RowGestureState extends State<_RowGesture> {
  static const _doubleTapWindow = Duration(milliseconds: 300);
  static const double _slop = 24;
  DateTime? _lastTap;
  Offset? _lastTapPos;
  Offset? _downPos;
  bool _secondaryDown = false;

  void _handleUp(Offset pos) {
    // Ignore a release that travelled far from its press (a drag/scroll).
    if (_downPos != null && (pos - _downPos!).distance > _slop) return;
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null &&
        now.difference(last) <= _doubleTapWindow &&
        _lastTapPos != null &&
        (pos - _lastTapPos!).distance <= _slop) {
      _lastTap = null;
      _lastTapPos = null;
      widget.onDoubleTap();
    } else {
      _lastTap = now;
      _lastTapPos = pos;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _downPos = e.localPosition;
        _secondaryDown =
            e.kind == PointerDeviceKind.mouse &&
            (e.buttons & kSecondaryMouseButton) != 0;
        if (_secondaryDown) {
          widget.onSecondaryTapDown(
            TapDownDetails(
              globalPosition: e.position,
              localPosition: e.localPosition,
              kind: e.kind,
            ),
          );
        }
      },
      onPointerUp: (e) {
        // The secondary (right) button already fired its menu on down; don't
        // also treat its release as a primary select/activate.
        if (_secondaryDown) {
          _secondaryDown = false;
          return;
        }
        _handleUp(e.localPosition);
      },
      child: widget.child,
    );
  }
}

/// Floating chip shown under the pointer while dragging a selection (D5).
class _DragChip extends StatelessWidget {
  final int count;
  final String label;
  const _DragChip({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = count > 1 ? '$count dosya' : label;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.elevated,
          border: Border.all(color: c.accent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator, size: 14, color: c.accent),
            const SizedBox(width: 6),
            Text(text, style: context.ui(size: 12, color: c.text)),
          ],
        ),
      ),
    );
  }
}
