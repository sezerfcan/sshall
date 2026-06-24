import '../models/connection.dart';
import '../models/folder.dart';
import '../models/vault_data.dart';
import '../resolve/connection_resolver.dart';

VaultData _with(
  VaultData v, {
  List<Folder>? folders,
  List<Connection>? connections,
}) => v.copyWith(folders: folders, connections: connections);

/// Next sibling order = max existing + 1 (0 if none).
int nextOrder(Iterable<int> orders) =>
    orders.isEmpty ? 0 : (orders.reduce((a, b) => a > b ? a : b) + 1);

/// Deterministically reorders a sibling group: takes [siblings] already in the
/// desired visual order and assigns each a dense, gap-free `order` of 0..n-1.
///
/// Pure list transform — no I/O, no UI. The [renumber] callback rebuilds each
/// item with its new order (e.g. `(folder, i) => folder.withOrder(i)`). This is
/// the single source of truth for renumbering both folder and connection sibling
/// groups, so reorder/move never leaves duplicate or sparse `order` keys
/// (ADR 0035 D1 — order integrity).
List<T> reorderSiblings<T>(
  List<T> siblings,
  T Function(T item, int index) renumber,
) => [for (var i = 0; i < siblings.length; i++) renumber(siblings[i], i)];

VaultData addFolder(
  VaultData v, {
  required String id,
  required String? parentId,
  required String name,
}) {
  final siblings = v.folders
      .where((f) => f.parentId == parentId)
      .map((f) => f.order);
  final folder = Folder(
    id: id,
    parentId: parentId,
    name: name,
    username: null,
    port: null,
    authRef: null,
    order: nextOrder(siblings),
  );
  return _with(v, folders: [...v.folders, folder]);
}

VaultData renameFolder(VaultData v, String id, String name) => _with(
  v,
  folders: [for (final f in v.folders) f.id == id ? f.rename(name) : f],
);

VaultData setFolderDefaults(
  VaultData v,
  String id, {
  String? username,
  int? port,
  String? authRef,
}) => _with(
  v,
  folders: [
    for (final f in v.folders)
      f.id == id
          ? f.withDefaults(username: username, port: port, authRef: authRef)
          : f,
  ],
);

/// Re-parents [id] under [newParentId]. No-op if it would create a cycle.
VaultData moveFolder(VaultData v, String id, String? newParentId) {
  if (wouldCreateCycle(id, newParentId, v.folders)) return v;
  return _with(
    v,
    folders: [
      for (final f in v.folders) f.id == id ? f.withParent(newParentId) : f,
    ],
  );
}

/// Re-parents [id] under [newParentId] AND positions it at [order] within the
/// destination level, then deterministically renumbers that level so the visual
/// order is gap-free (ADR 0035 D1). Same-level reorder goes through this path too
/// (pass the unchanged parent). No-op when it would create a cycle
/// ([wouldCreateCycle] reuse) or when [id] does not exist.
///
/// [order] is the desired 0-based insertion index among the destination
/// siblings (after [id] is removed from its old slot); it is clamped to the
/// valid range. One pure [VaultData] transform → the caller persists it in a
/// single `store.mutate` revision (atomic).
VaultData moveFolderOrdered(
  VaultData v,
  String id, {
  required String? newParentId,
  required int order,
}) {
  if (!v.folders.any((f) => f.id == id)) return v;
  if (wouldCreateCycle(id, newParentId, v.folders)) return v;

  final moving = v.folders
      .firstWhere((f) => f.id == id)
      .withParent(newParentId);

  // Destination siblings in current visual order, excluding the moved folder.
  final dest =
      [
        for (final f in v.folders)
          if (f.id != id && f.parentId == newParentId) f,
      ]..sort(
        (a, b) => a.order != b.order
            ? a.order.compareTo(b.order)
            : a.name.compareTo(b.name),
      );

  final idx = order.clamp(0, dest.length);
  dest.insert(idx, moving);
  final renumbered = reorderSiblings(dest, (f, i) => f.withOrder(i));
  final byId = {for (final f in renumbered) f.id: f};

  return _with(v, folders: [for (final f in v.folders) byId[f.id] ?? f]);
}

/// Deletes [id], re-parenting its child folders and connections to its parent
/// (grandparent from the children's view; null = root).
VaultData deleteFolderReparent(VaultData v, String id) {
  final matches = v.folders.where((f) => f.id == id);
  if (matches.isEmpty) return v;
  final target = matches.first;
  final gp = target.parentId;
  final folders = [
    for (final f in v.folders)
      if (f.id != id) (f.parentId == id ? f.withParent(gp) : f),
  ];
  final connections = [
    for (final c in v.connections) c.folderId == id ? c.withFolder(gp) : c,
  ];
  return _with(v, folders: folders, connections: connections);
}
