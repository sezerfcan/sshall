import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/folders/connection_ops.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';

Connection _conn(String id, {String? authRef, String? folderId}) => Connection(
  id: id,
  label: id,
  host: 'h',
  folderId: folderId,
  username: null,
  port: null,
  authRef: authRef,
  tags: const [],
  order: 0,
);

Folder _folder(String id, {String? authRef}) => Folder(
  id: id,
  parentId: null,
  name: id,
  username: 'root',
  port: 22,
  authRef: authRef,
  order: 0,
);

Identity _id(String id, {String label = 'k'}) => Identity(
  id: id,
  label: label,
  type: IdentityType.privateKey,
  secret: 'PEM',
  passphrase: null,
  fingerprint: 'SHA256:$id',
);

void main() {
  group('identityUsage (D4)', () {
    test('counts referencing connections + folders', () {
      final v = VaultData(
        connections: [
          _conn('c1', authRef: 'k1'),
          _conn('c2', authRef: 'k1'),
        ],
        folders: [
          _folder('f1', authRef: 'k1'),
          _folder('f2', authRef: 'other'),
        ],
        identities: [_id('k1')],
        pins: const [],
      );
      expect(identityUsage(v, 'k1'), 3);
    });

    test('returns 0 for an unreferenced identity', () {
      final v = VaultData(
        connections: [_conn('c1', authRef: 'k2')],
        folders: const [],
        identities: [_id('k1'), _id('k2')],
        pins: const [],
      );
      expect(identityUsage(v, 'k1'), 0);
    });
  });

  group('referencing (D4)', () {
    test('returns the exact referencing connection + folder set', () {
      final v = VaultData(
        connections: [
          _conn('c1', authRef: 'k1'),
          _conn('c2', authRef: 'x'),
        ],
        folders: [_folder('f1', authRef: 'k1')],
        identities: [_id('k1')],
        pins: const [],
      );
      final r = referencing(v, 'k1');
      expect(r.connections.map((c) => c.id), ['c1']);
      expect(r.folders.map((f) => f.id), ['f1']);
    });
  });

  group('renameIdentity (D4)', () {
    test('changes only the label; secret/fingerprint and refs untouched', () {
      final v = VaultData(
        connections: [_conn('c1', authRef: 'k1')],
        folders: const [],
        identities: [_id('k1', label: 'old')],
        pins: const [],
      );
      final out = renameIdentity(v, 'k1', 'new');
      final id = out.identities.single;
      expect(id.label, 'new');
      expect(id.secret, 'PEM');
      expect(id.fingerprint, 'SHA256:k1');
      // The referencing connection is untouched (still points at the same id).
      expect(out.connections.single.authRef, 'k1');
    });
  });

  group('deleteIdentity (D4) — no dangling refs', () {
    test('removes the identity AND nulls every referencing authRef', () {
      final v = VaultData(
        connections: [
          _conn('c1', authRef: 'k1'),
          _conn('c2', authRef: 'k1'),
          _conn('c3', authRef: 'keep'),
        ],
        folders: [
          _folder('f1', authRef: 'k1'),
          _folder('f2', authRef: 'keep'),
        ],
        identities: [_id('k1'), _id('keep')],
        pins: const [],
      );
      final out = deleteIdentity(v, 'k1');

      // Identity gone, the other kept.
      expect(out.identities.map((i) => i.id), ['keep']);

      // Every referencing connection/folder is now identity-less.
      expect(out.connections.firstWhere((c) => c.id == 'c1').authRef, isNull);
      expect(out.connections.firstWhere((c) => c.id == 'c2').authRef, isNull);
      expect(out.folders.firstWhere((f) => f.id == 'f1').authRef, isNull);

      // The unrelated references are untouched.
      expect(out.connections.firstWhere((c) => c.id == 'c3').authRef, 'keep');
      expect(out.folders.firstWhere((f) => f.id == 'f2').authRef, 'keep');

      // CRITICAL: nothing left points at the deleted id (no dangling).
      expect(out.connections.any((c) => c.authRef == 'k1'), isFalse);
      expect(out.folders.any((f) => f.authRef == 'k1'), isFalse);
    });

    test('preserves a referencing folder\'s other inheritable defaults', () {
      final v = VaultData(
        connections: const [],
        folders: [_folder('f1', authRef: 'k1')], // username root, port 22
        identities: [_id('k1')],
        pins: const [],
      );
      final f = deleteIdentity(v, 'k1').folders.single;
      expect(f.authRef, isNull);
      expect(f.username, 'root'); // not clobbered
      expect(f.port, 22);
    });
  });
}
