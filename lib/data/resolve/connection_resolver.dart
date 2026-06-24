import '../models/connection.dart';
import '../models/folder.dart';

/// A connection with its inheritable fields resolved against the folder chain.
class ResolvedConnection {
  final Connection connection;

  /// Resolved username; null means unresolved → connect must be blocked.
  final String? username;

  /// Resolved port; always set (falls back to 22).
  final int port;

  /// Resolved identity id; null means unresolved → connect must be blocked.
  final String? authRef;

  const ResolvedConnection({
    required this.connection,
    required this.username,
    required this.port,
    required this.authRef,
  });
}

/// Resolves [c]'s inheritable fields (username/port/authRef) field-by-field,
/// nearest-wins: the connection's own value if set, else the first ancestor
/// folder that sets it. port falls back to 22. The walk is cycle-guarded.
ResolvedConnection resolve(Connection c, List<Folder> folders) {
  final byId = {for (final f in folders) f.id: f};

  String? username = c.username;
  int? port = c.port;
  String? authRef = c.authRef;

  final visited = <String>{};
  String? parentId = c.folderId;
  while (parentId != null &&
      byId.containsKey(parentId) &&
      visited.add(parentId)) {
    final f = byId[parentId]!;
    username ??= f.username;
    port ??= f.port;
    authRef ??= f.authRef;
    parentId = f.parentId;
  }

  return ResolvedConnection(
    connection: c,
    username: username,
    port: port ?? 22,
    authRef: authRef,
  );
}

/// True if re-parenting [folderId] under [newParentId] would create a cycle —
/// i.e. [newParentId] is [folderId] itself or one of its descendants.
bool wouldCreateCycle(
    String folderId, String? newParentId, List<Folder> folders) {
  if (newParentId == null) return false;
  if (newParentId == folderId) return true;
  final byId = {for (final f in folders) f.id: f};
  final visited = <String>{};
  String? cur = newParentId;
  while (cur != null && byId.containsKey(cur) && visited.add(cur)) {
    if (cur == folderId) return true;
    cur = byId[cur]!.parentId;
  }
  return false;
}
