import '../models/connection.dart';
import '../models/folder.dart';
import '../models/identity.dart';
import '../../services/ssh/ssh_messages.dart';
import 'connection_resolver.dart';

/// The identity in [identities] with id [id], or null if none / dangling ref.
Identity? identityById(List<Identity> identities, String id) {
  for (final i in identities) {
    if (i.id == id) return i;
  }
  return null;
}

/// The connection in [connections] with id [id], or null when [id] is null or
/// no longer present (e.g. it was deleted out from under a selection).
Connection? connectionById(List<Connection> connections, String? id) {
  if (id == null) return null;
  for (final c in connections) {
    if (c.id == id) return c;
  }
  return null;
}

/// Resolves [c] against [folders] + [identities] into [SshConnectParams], or
/// null when the connection is not yet connectable: username or authRef is
/// unresolved, or the resolved authRef points at a deleted identity.
///
/// Pure: no store, no ref. Extracted from `_ConnectionsViewState` so the
/// "saved connection -> connect params" mapping can be unit-tested without the
/// widget — the terminal (`_connectSaved`) and SFTP (`_openSftp`) paths share
/// exactly this resolution.
SshConnectParams? paramsFor(
  Connection c, {
  required List<Folder> folders,
  required List<Identity> identities,
}) {
  final r = resolve(c, folders);
  if (r.username == null || r.authRef == null) return null;
  final id = identityById(identities, r.authRef!);
  if (id == null) return null; // dangling authRef
  return SshConnectParams(
    host: c.host,
    port: r.port,
    username: r.username!,
    password: id.type == IdentityType.password ? id.secret : null,
    privateKeyPem: id.type == IdentityType.privateKey ? id.secret : null,
    keyPassphrase: id.passphrase,
  );
}
