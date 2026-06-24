/// A node in the connection tree. Folders nest via [parentId] (adjacency list);
/// [parentId] == null means root level. A folder may declare default
/// [username]/[port]/[authRef] that descendant connections inherit (ADR 0010).
class Folder {
  final String id;
  final String? parentId;
  final String name;

  /// Inheritable defaults. null = not set at this level (inherit from above).
  final String? username;
  final int? port;
  final String? authRef;

  /// Sibling ordering (ascending).
  final int order;

  const Folder({
    required this.id,
    required this.parentId,
    required this.name,
    required this.username,
    required this.port,
    required this.authRef,
    required this.order,
  });

  Folder withParent(String? parentId) => Folder(
    id: id,
    parentId: parentId,
    name: name,
    username: username,
    port: port,
    authRef: authRef,
    order: order,
  );

  /// Returns a copy with a new sibling [order] (ADR 0035 D1 reorder/move).
  Folder withOrder(int order) => Folder(
    id: id,
    parentId: parentId,
    name: name,
    username: username,
    port: port,
    authRef: authRef,
    order: order,
  );

  Folder rename(String name) => Folder(
    id: id,
    parentId: parentId,
    name: name,
    username: username,
    port: port,
    authRef: authRef,
    order: order,
  );

  /// Replaces ALL three inheritable defaults wholesale. Pass null to clear a
  /// field back to "inherit". The editor always supplies the full new set.
  Folder withDefaults({
    required String? username,
    required int? port,
    required String? authRef,
  }) => Folder(
    id: id,
    parentId: parentId,
    name: name,
    username: username,
    port: port,
    authRef: authRef,
    order: order,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'parentId': parentId,
    'name': name,
    'username': username,
    'port': port,
    'authRef': authRef,
    'order': order,
  };

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
    id: j['id'] as String,
    parentId: j['parentId'] as String?,
    name: j['name'] as String,
    username: j['username'] as String?,
    port: j['port'] as int?,
    authRef: j['authRef'] as String?,
    order: (j['order'] as int?) ?? 0,
  );
}
