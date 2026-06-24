import '../models/connection.dart';
import '../models/folder.dart';
import '../resolve/connection_resolver.dart';

class TreeRow {
  final bool isFolder;
  final Folder? folder;
  final Connection? connection;
  final int depth;
  const TreeRow.folder(this.folder, this.depth)
      : isFolder = true,
        connection = null;
  const TreeRow.connection(this.connection, this.depth)
      : isFolder = false,
        folder = null;
}

/// Flattens the folder/connection tree into display rows, depth-first. At each
/// level: subfolders first (sorted by order then name), then connections
/// (sorted by order then label). A folder whose id is not in [expanded] has its
/// subtree omitted.
List<TreeRow> buildTreeRows(
    List<Folder> folders, List<Connection> conns, Set<String> expanded) {
  final childFolders = <String?, List<Folder>>{};
  for (final f in folders) {
    (childFolders[f.parentId] ??= []).add(f);
  }
  final childConns = <String?, List<Connection>>{};
  for (final c in conns) {
    (childConns[c.folderId] ??= []).add(c);
  }
  for (final list in childFolders.values) {
    list.sort((a, b) => a.order != b.order
        ? a.order.compareTo(b.order)
        : a.name.compareTo(b.name));
  }
  for (final list in childConns.values) {
    list.sort((a, b) => a.order != b.order
        ? a.order.compareTo(b.order)
        : a.label.compareTo(b.label));
  }

  final rows = <TreeRow>[];
  void walk(String? parentId, int depth) {
    for (final f in childFolders[parentId] ?? const []) {
      rows.add(TreeRow.folder(f, depth));
      if (expanded.contains(f.id)) walk(f.id, depth + 1);
    }
    for (final c in childConns[parentId] ?? const []) {
      rows.add(TreeRow.connection(c, depth));
    }
  }

  walk(null, 0);
  return rows;
}

/// Filters the tree to connections matching [query] (case-insensitive) on
/// label, host, resolved username, or any tag, keeping every ancestor folder of
/// a match so the tree context is preserved. The username is matched against its
/// resolved value, so a host that inherits e.g. 'deploy' from a folder is found
/// when searching 'deploy'. Empty/blank query returns the inputs unchanged.
({List<Folder> folders, List<Connection> conns}) filterTree(
    List<Folder> folders, List<Connection> conns, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return (folders: folders, conns: conns);

  bool matches(Connection c) {
    if (c.label.toLowerCase().contains(q) ||
        c.host.toLowerCase().contains(q) ||
        c.tags.any((t) => t.toLowerCase().contains(q))) {
      return true;
    }
    final user = resolve(c, folders).username;
    return user != null && user.toLowerCase().contains(q);
  }

  final byId = {for (final f in folders) f.id: f};
  final keptConns = conns.where(matches).toList();

  final keepFolders = <String>{};
  for (final c in keptConns) {
    var pid = c.folderId;
    final guard = <String>{};
    while (pid != null && byId.containsKey(pid) && guard.add(pid)) {
      keepFolders.add(pid);
      pid = byId[pid]!.parentId;
    }
  }
  return (
    folders: folders.where((f) => keepFolders.contains(f.id)).toList(),
    conns: keptConns,
  );
}
