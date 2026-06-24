import '../models/connection.dart';
import '../models/folder.dart';
import '../models/identity.dart';
import '../models/vault_data.dart';
import 'folder_ops.dart';

/// Three-state edit for an inheritable scalar field: inherit from the folder
/// chain (null) or set a concrete value.
sealed class FieldEdit<T> {
  const FieldEdit();
}

class Inherit<T> extends FieldEdit<T> {
  const Inherit();
}

class SetValue<T> extends FieldEdit<T> {
  final T value;
  const SetValue(this.value);
}

T? _resolveField<T>(FieldEdit<T> e) => switch (e) {
  Inherit<T>() => null,
  SetValue<T>(:final value) => value,
};

/// What to do with the connection's identity (authRef) on edit.
sealed class IdentityEdit {
  const IdentityEdit();
}

/// Drop the dedicated identity; inherit authRef from the folder chain.
class IdentityInherit extends IdentityEdit {
  const IdentityInherit();
}

/// Leave the existing authRef + Identity untouched.
class IdentityKeep extends IdentityEdit {
  const IdentityKeep();
}

class IdentitySetPassword extends IdentityEdit {
  final String password;
  const IdentitySetPassword(this.password);
}

class IdentitySetKey extends IdentityEdit {
  final String pem;
  final String? passphrase;
  const IdentitySetKey(this.pem, this.passphrase);
}

/// Updates [connId]'s metadata, inheritable overrides, and identity in one pure
/// transform. [newIdentityId] is used ONLY when a concrete identity must be
/// created (inherit -> concrete); callers pass a fresh unique id.
VaultData updateConnection(
  VaultData v, {
  required String connId,
  required String label,
  required String host,
  required String? folderId,
  required List<String> tags,
  required FieldEdit<String> username,
  required FieldEdit<int> port,
  required IdentityEdit identity,
  required bool docker,
  required String? dockerBinary,
  required String newIdentityId,
}) {
  final idx = v.connections.indexWhere((c) => c.id == connId);
  if (idx < 0) return v;
  final current = v.connections[idx];
  final priorAuthRef = current.authRef;

  String? newAuthRef = priorAuthRef;
  var identities = v.identities;

  switch (identity) {
    case IdentityKeep():
      break;
    case IdentityInherit():
      newAuthRef = null;
      if (priorAuthRef != null) {
        final sharedByOther = v.connections.any(
          (c) => c.id != connId && c.authRef == priorAuthRef,
        );
        if (!sharedByOther) {
          identities = [
            for (final i in identities)
              if (i.id != priorAuthRef) i,
          ];
        }
      }
    case IdentitySetPassword(:final password):
      final id = Identity(
        id: priorAuthRef ?? newIdentityId,
        label: label,
        type: IdentityType.password,
        secret: password,
        passphrase: null,
      );
      newAuthRef = id.id;
      identities = _upsertIdentity(identities, id);
    case IdentitySetKey(:final pem, :final passphrase):
      final id = Identity(
        id: priorAuthRef ?? newIdentityId,
        label: label,
        type: IdentityType.privateKey,
        secret: pem,
        passphrase: passphrase,
      );
      newAuthRef = id.id;
      identities = _upsertIdentity(identities, id);
  }

  final updated = current.copyWith(
    label: label,
    host: host,
    folderId: folderId,
    tags: tags,
    username: _resolveField(username),
    port: _resolveField(port),
    authRef: newAuthRef,
    docker: docker,
    dockerBinary: dockerBinary,
  );

  final connections = [
    for (final c in v.connections) c.id == connId ? updated : c,
  ];
  return v.copyWith(connections: connections, identities: identities);
}

// ── Pure reorder / move ops (ADR 0035 D1) ─────────────────────────────────
// These power the connection tree's drag-and-drop. They are pure VaultData
// transforms (no UI, no I/O); the sidebar calls them and persists the result in
// a SINGLE store.mutate revision (atomic). They keep sibling `order` keys dense
// and gap-free via [reorderSiblings] (folder_ops.dart) so the visible
// order-then-label sort stays deterministic. No schema change: only the existing
// `folderId` + `order` fields are written.

/// Moves [connId] into [folderId] (null = root) at the destination index
/// [order], then deterministically renumbers BOTH the destination group (so the
/// insertion index is honored) AND the source group (so no gap is left behind).
/// Untouched sibling groups keep their order. No-op when [connId] does not exist.
///
/// [order] is the 0-based slot among the destination connections after [connId]
/// is removed from its old slot; it is clamped to the valid range. A host can
/// never form a cycle (only folder nesting can), so there is no cycle guard here.
VaultData moveConnection(
  VaultData v,
  String connId, {
  required String? folderId,
  required int order,
}) {
  final idx = v.connections.indexWhere((c) => c.id == connId);
  if (idx < 0) return v;
  final current = v.connections[idx];
  final sourceFolderId = current.folderId;
  final moving = current.copyWith(folderId: folderId);

  // Destination siblings in current visual order, excluding the moved host.
  final dest =
      [
        for (final c in v.connections)
          if (c.id != connId && c.folderId == folderId) c,
      ]..sort(
        (a, b) => a.order != b.order
            ? a.order.compareTo(b.order)
            : a.label.compareTo(b.label),
      );
  final destIdx = order.clamp(0, dest.length);
  dest.insert(destIdx, moving);
  final destRenumbered = reorderSiblings(dest, (c, i) => c.copyWith(order: i));

  // Source siblings renumber too (gap-free) when the move crossed folders.
  final byId = {for (final c in destRenumbered) c.id: c};
  if (sourceFolderId != folderId) {
    final source =
        [
          for (final c in v.connections)
            if (c.id != connId && c.folderId == sourceFolderId) c,
        ]..sort(
          (a, b) => a.order != b.order
              ? a.order.compareTo(b.order)
              : a.label.compareTo(b.label),
        );
    final sourceRenumbered = reorderSiblings(
      source,
      (c, i) => c.copyWith(order: i),
    );
    for (final c in sourceRenumbered) {
      byId[c.id] = c;
    }
  }

  return v.copyWith(
    connections: [for (final c in v.connections) byId[c.id] ?? c],
  );
}

/// Same-folder reorder: positions [connId] at [newIndex] among its current
/// siblings and renumbers them gap-free (folderId unchanged). Convenience over
/// [moveConnection] for the in-group drag case; kept as a separate signature for
/// test readability. No-op when [connId] does not exist.
VaultData reorderConnection(VaultData v, String connId, int newIndex) {
  final idx = v.connections.indexWhere((c) => c.id == connId);
  if (idx < 0) return v;
  return moveConnection(
    v,
    connId,
    folderId: v.connections[idx].folderId,
    order: newIndex,
  );
}

List<Identity> _upsertIdentity(List<Identity> ids, Identity id) =>
    ids.any((i) => i.id == id.id)
    ? [for (final i in ids) i.id == id.id ? id : i]
    : [...ids, id];

/// Deletes [connId] and its identity (only if no other connection uses it).
/// Host-key pins are left untouched (a pin is host-scoped, not connection-
/// scoped; other connections may use the same host).
VaultData deleteConnection(VaultData v, String connId) {
  final idx = v.connections.indexWhere((c) => c.id == connId);
  if (idx < 0) return v;
  final authRef = v.connections[idx].authRef;
  final connections = [
    for (final c in v.connections)
      if (c.id != connId) c,
  ];
  var identities = v.identities;
  if (authRef != null && !connections.any((c) => c.authRef == authRef)) {
    identities = [
      for (final i in identities)
        if (i.id != authRef) i,
    ];
  }
  return v.copyWith(connections: connections, identities: identities);
}

// ── Identity-centric pure ops (ADR 0033 / D4) ──────────────────────────────
// These power the vault's identity manager. They mirror the orphan-drop
// precedent above: an identity is referenced by a STABLE id (authRef) on
// connections AND folders (ADR 0010 inheritance), so editing the identity is
// safe and deleting it nulls every referencing authRef IN THE SAME transform —
// never leaving a dangling id (resolver then falls through to inheritance, and
// paramsFor is already graceful on a null authRef).

/// Number of connections + folders whose authRef points at [identityId].
/// Drives the usage badge ("N bağlantı") and the delete-confirmation count.
int identityUsage(VaultData v, String identityId) {
  var n = 0;
  for (final c in v.connections) {
    if (c.authRef == identityId) n++;
  }
  for (final f in v.folders) {
    if (f.authRef == identityId) n++;
  }
  return n;
}

/// The connections + folders that reference [identityId] (for the detail
/// view's "Kullanan bağlantılar" list and jump-to-connection).
({List<Connection> connections, List<Folder> folders}) referencing(
  VaultData v,
  String identityId,
) {
  final connections = [
    for (final c in v.connections)
      if (c.authRef == identityId) c,
  ];
  final folders = [
    for (final f in v.folders)
      if (f.authRef == identityId) f,
  ];
  return (connections: connections, folders: folders);
}

/// Renames an identity by id, changing ONLY its label. References use the
/// stable id, so no cascade is needed (D4).
VaultData renameIdentity(VaultData v, String id, String newLabel) {
  final identities = [
    for (final i in v.identities) i.id == id ? i.copyWith(label: newLabel) : i,
  ];
  return v.copyWith(identities: identities);
}

/// Deletes the identity [id] AND nulls the matching authRef on every
/// referencing connection and folder in the SAME transform, so no dangling id
/// is ever left behind (D4). The referencing nodes become identity-less
/// (resolver inheritance / paramsFor handle the null gracefully).
VaultData deleteIdentity(VaultData v, String id) {
  final identities = [
    for (final i in v.identities)
      if (i.id != id) i,
  ];
  final connections = [
    for (final c in v.connections)
      c.authRef == id ? c.copyWith(authRef: null) : c,
  ];
  final folders = [
    for (final f in v.folders)
      f.authRef == id
          ? f.withDefaults(username: f.username, port: f.port, authRef: null)
          : f,
  ];
  return v.copyWith(
    identities: identities,
    connections: connections,
    folders: folders,
  );
}
