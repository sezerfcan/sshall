import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/folders/connection_ops.dart';

Connection _conn(
  String id, {
  String? authRef,
  String? username,
  int? port,
  String? folderId,
  int order = 0,
}) => Connection(
  id: id,
  label: id,
  host: 'h',
  folderId: folderId,
  username: username,
  port: port,
  authRef: authRef,
  tags: const [],
  order: order,
);

Identity _id(
  String id, {
  IdentityType type = IdentityType.password,
  String secret = 's',
}) => Identity(id: id, label: id, type: type, secret: secret, passphrase: null);

VaultData _vault({
  List<Connection> conns = const [],
  List<Identity> ids = const [],
}) => VaultData(
  connections: conns,
  folders: const [],
  identities: ids,
  pins: const [],
);

VaultData _update(
  VaultData v,
  String connId, {
  String label = 'web',
  String host = 'h',
  String? folderId,
  FieldEdit<String> username = const SetValue('root'),
  FieldEdit<int> port = const SetValue(22),
  IdentityEdit identity = const IdentityKeep(),
  bool docker = false,
  String? dockerBinary,
  String newIdentityId = 'i-new',
}) => updateConnection(
  v,
  connId: connId,
  label: label,
  host: host,
  folderId: folderId,
  tags: const [],
  username: username,
  port: port,
  identity: identity,
  docker: docker,
  dockerBinary: dockerBinary,
  newIdentityId: newIdentityId,
);

void main() {
  test('updates metadata and concrete overrides', () {
    final v0 = _vault(
      conns: [_conn('c1', authRef: 'i1')],
      ids: [_id('i1')],
    );
    final v = _update(
      v0,
      'c1',
      label: 'db',
      host: 'h2',
      username: const SetValue('deploy'),
      port: const SetValue(2222),
    );
    final c = v.connections.single;
    expect(c.label, 'db');
    expect(c.host, 'h2');
    expect(c.username, 'deploy');
    expect(c.port, 2222);
  });

  test('username/port can be set to inherit (null)', () {
    final v0 = _vault(
      conns: [_conn('c1', authRef: 'i1', username: 'root', port: 22)],
      ids: [_id('i1')],
    );
    final v = _update(
      v0,
      'c1',
      username: const Inherit(),
      port: const Inherit(),
    );
    expect(v.connections.single.username, isNull);
    expect(v.connections.single.port, isNull);
  });

  test('IdentityKeep leaves authRef and identities untouched', () {
    final v0 = _vault(
      conns: [_conn('c1', authRef: 'i1')],
      ids: [_id('i1', secret: 'old')],
    );
    final v = _update(v0, 'c1', identity: const IdentityKeep());
    expect(v.connections.single.authRef, 'i1');
    expect(v.identities.single.secret, 'old');
  });

  test('IdentitySetPassword updates the existing identity in place', () {
    final v0 = _vault(
      conns: [_conn('c1', authRef: 'i1')],
      ids: [_id('i1', secret: 'old')],
    );
    final v = _update(
      v0,
      'c1',
      label: 'web',
      identity: const IdentitySetPassword('newpass'),
    );
    expect(v.connections.single.authRef, 'i1'); // same id
    final id = v.identities.single;
    expect(id.id, 'i1');
    expect(id.type, IdentityType.password);
    expect(id.secret, 'newpass');
    expect(id.label, 'web'); // synced to connection label
    expect(v.identities.length, 1); // no new identity
  });

  test('IdentitySetKey updates type+secret+passphrase in place', () {
    final v0 = _vault(
      conns: [_conn('c1', authRef: 'i1')],
      ids: [_id('i1')],
    );
    final v = _update(
      v0,
      'c1',
      identity: const IdentitySetKey('PEMDATA', 'phrase'),
    );
    final id = v.identities.single;
    expect(id.type, IdentityType.privateKey);
    expect(id.secret, 'PEMDATA');
    expect(id.passphrase, 'phrase');
  });

  test(
    'concrete -> inherit clears authRef and drops the orphaned identity',
    () {
      final v0 = _vault(
        conns: [_conn('c1', authRef: 'i1')],
        ids: [_id('i1')],
      );
      final v = _update(v0, 'c1', identity: const IdentityInherit());
      expect(v.connections.single.authRef, isNull);
      expect(v.identities, isEmpty); // orphan removed
    },
  );

  test(
    'concrete -> inherit keeps identity if another connection shares it',
    () {
      final v0 = _vault(
        conns: [
          _conn('c1', authRef: 'i1'),
          _conn('c2', authRef: 'i1'),
        ],
        ids: [_id('i1')],
      );
      final v = _update(v0, 'c1', identity: const IdentityInherit());
      expect(v.connections.firstWhere((c) => c.id == 'c1').authRef, isNull);
      expect(v.identities.length, 1); // still used by c2
    },
  );

  test('inherit -> concrete creates a new identity with newIdentityId', () {
    final v0 = _vault(conns: [_conn('c1', authRef: null)], ids: const []);
    final v = _update(
      v0,
      'c1',
      label: 'web',
      identity: const IdentitySetPassword('pw'),
      newIdentityId: 'i-new',
    );
    expect(v.connections.single.authRef, 'i-new');
    final id = v.identities.single;
    expect(id.id, 'i-new');
    expect(id.secret, 'pw');
    expect(id.label, 'web');
  });

  test('unknown connId is a no-op', () {
    final v0 = _vault(
      conns: [_conn('c1', authRef: 'i1')],
      ids: [_id('i1')],
    );
    expect(_update(v0, 'missing'), v0);
  });

  group('moveConnection / reorderConnection (ADR 0035 D1)', () {
    test(
      'moveConnection to another folder sets folderId + renumbers both groups',
      () {
        // dest folder 'b' has b0,b1; source folder 'a' has a0,(moved),a2.
        final v0 = _vault(
          conns: [
            _conn('a0', folderId: 'a', order: 0),
            _conn('m', folderId: 'a', order: 1),
            _conn('a2', folderId: 'a', order: 2),
            _conn('b0', folderId: 'b', order: 0),
            _conn('b1', folderId: 'b', order: 1),
            _conn('root0', folderId: null, order: 0),
          ],
        );
        final v = moveConnection(v0, 'm', folderId: 'b', order: 1);
        Connection by(String id) => v.connections.firstWhere((c) => c.id == id);

        // Moved host now lives in 'b' at index 1.
        expect(by('m').folderId, 'b');
        expect(by('m').order, 1);
        // Destination 'b' renumbered gap-free 0..2 in insertion order.
        expect(by('b0').order, 0);
        expect(by('m').order, 1);
        expect(by('b1').order, 2);
        // Source 'a' renumbered gap-free (the hole at order 1 is gone).
        expect(by('a0').order, 0);
        expect(by('a2').order, 1);
        // An untouched group (root) keeps its order.
        expect(by('root0').order, 0);
      },
    );

    test(
      'reorderConnection within a folder renumbers to the new visual order',
      () {
        // c0,c1,c2 in one folder; move c2 to the front.
        final v0 = _vault(
          conns: [
            _conn('c0', folderId: 'f', order: 0),
            _conn('c1', folderId: 'f', order: 1),
            _conn('c2', folderId: 'f', order: 2),
          ],
        );
        final v = reorderConnection(v0, 'c2', 0);
        Connection by(String id) => v.connections.firstWhere((c) => c.id == id);
        expect(by('c2').order, 0);
        expect(by('c0').order, 1);
        expect(by('c1').order, 2);
        // folderId never changes for a same-folder reorder.
        expect(by('c2').folderId, 'f');
      },
    );

    test('moveConnection clamps an out-of-range index to the end', () {
      final v0 = _vault(
        conns: [
          _conn('c0', folderId: null, order: 0),
          _conn('m', folderId: 'f', order: 0),
        ],
      );
      final v = moveConnection(v0, 'm', folderId: null, order: 99);
      Connection by(String id) => v.connections.firstWhere((c) => c.id == id);
      // Appended after the existing root host.
      expect(by('c0').order, 0);
      expect(by('m').order, 1);
      expect(by('m').folderId, isNull);
    });

    test('moveConnection on an unknown id is a no-op', () {
      final v0 = _vault(conns: [_conn('c0', folderId: 'f', order: 0)]);
      expect(moveConnection(v0, 'missing', folderId: null, order: 0), v0);
    });
  });

  group('deleteConnection', () {
    test('removes the connection and its sole-owned identity', () {
      final v0 = _vault(
        conns: [_conn('c1', authRef: 'i1')],
        ids: [_id('i1')],
      );
      final v = deleteConnection(v0, 'c1');
      expect(v.connections, isEmpty);
      expect(v.identities, isEmpty);
    });

    test('keeps a shared identity', () {
      final v0 = _vault(
        conns: [
          _conn('c1', authRef: 'i1'),
          _conn('c2', authRef: 'i1'),
        ],
        ids: [_id('i1')],
      );
      final v = deleteConnection(v0, 'c1');
      expect(v.connections.single.id, 'c2');
      expect(v.identities.length, 1);
    });

    test('unknown id is a no-op', () {
      final v0 = _vault(
        conns: [_conn('c1', authRef: 'i1')],
        ids: [_id('i1')],
      );
      expect(deleteConnection(v0, 'missing'), v0);
    });

    test(
      'a connection that inherits identity (null authRef) drops no identity',
      () {
        final v0 = _vault(
          conns: [_conn('c1', authRef: null)],
          ids: [_id('i1')],
        );
        final v = deleteConnection(v0, 'c1');
        expect(v.connections, isEmpty);
        expect(v.identities.length, 1);
      },
    );
  });
}
