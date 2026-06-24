import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/data/models/vault_data.dart';

void main() {
  test('VaultData round-trips through JSON', () {
    const v = VaultData(
      connections: [
        Connection(
          id: 'c1',
          label: 'prod',
          host: 'example.com',
          folderId: null,
          username: 'root',
          port: 22,
          authRef: 'i1',
          tags: [],
          order: 0,
        ),
      ],
      folders: [],
      identities: [
        Identity(
          id: 'i1',
          label: 'prod-pass',
          type: IdentityType.password,
          secret: 's3cret',
          passphrase: null,
        ),
      ],
      pins: [
        HostKeyPin(
          hostPort: 'example.com:22',
          keyType: 'ssh-ed25519',
          sha256: 'AbC123',
        ),
      ],
    );

    final restored = VaultData.fromJson(v.toJson());
    expect(restored.connections.single.host, 'example.com');
    expect(restored.identities.single.type, IdentityType.password);
    expect(restored.identities.single.secret, 's3cret');
    expect(restored.pins.single.sha256, 'AbC123');
  });

  test('VaultData.empty has no entries', () {
    final v = VaultData.empty();
    expect(v.connections, isEmpty);
    expect(v.identities, isEmpty);
    expect(v.pins, isEmpty);
  });

  test('VaultData.fromJson tolerates a legacy body with no folders key', () {
    final legacy = {
      'connections': [
        {'id': 'c1', 'label': 'box', 'host': 'h', 'port': 22,
         'username': 'u', 'authRef': 'i1'},
      ],
      'identities': [
        {'id': 'i1', 'label': 'p', 'type': 'password', 'secret': 's',
         'passphrase': null},
      ],
      'pins': [],
      // no 'folders' key
    };
    final v = VaultData.fromJson(legacy);
    expect(v.folders, isEmpty);
    expect(v.connections.single.host, 'h');
    expect(v.connections.single.username, 'u'); // legacy explicit value
  });

  test('VaultData.fromJson tolerates entirely missing list keys', () {
    // A truncated/forward-schema body must not throw; missing lists default to
    // empty rather than crashing the whole unlock.
    final v = VaultData.fromJson(<String, dynamic>{});
    expect(v.connections, isEmpty);
    expect(v.identities, isEmpty);
    expect(v.pins, isEmpty);
    expect(v.folders, isEmpty);
  });

  test('VaultData.fromJson skips a single corrupt record, keeps the rest', () {
    // One broken connection (missing required `host`) and one broken identity
    // (unknown `type` enum) must NOT take down the whole vault: the good
    // records survive, the bad ones are dropped.
    final body = {
      'connections': [
        {'id': 'good', 'label': 'ok', 'host': 'h', 'port': 22},
        {'id': 'bad', 'label': 'broken'}, // no host -> drop
        'not-even-a-map', // wrong element type -> drop
      ],
      'identities': [
        {'id': 'i-good', 'label': 'p', 'type': 'password', 'secret': 's'},
        {'id': 'i-bad', 'label': 'x', 'type': 'quantumKey', 'secret': 's'},
      ],
      'pins': [
        {'hostPort': 'h:22', 'keyType': 'ssh-ed25519', 'sha256': 'AAA'},
        {'hostPort': 'h:22'}, // missing sha256 -> drop
      ],
      'folders': [
        {'id': 'f1', 'name': 'work'},
        {'name': 'noid'}, // missing id -> drop
      ],
    };
    final v = VaultData.fromJson(body);
    expect(v.connections.map((c) => c.id), ['good']);
    expect(v.identities.map((i) => i.id), ['i-good']);
    expect(v.pins.single.hostPort, 'h:22');
    expect(v.folders.single.id, 'f1');
  });

  test('VaultData.copyWith returns an identical copy when no args given', () {
    const v = VaultData(
      connections: [
        Connection(
          id: 'c1', label: 'box', host: 'h', folderId: null,
          username: 'u', port: 22, authRef: 'i1', tags: [], order: 0,
        ),
      ],
      folders: [
        Folder(id: 'f1', parentId: null, name: 'work',
            username: null, port: null, authRef: null, order: 0),
      ],
      identities: [
        Identity(id: 'i1', label: 'p', type: IdentityType.password,
            secret: 's', passphrase: null),
      ],
      pins: [
        HostKeyPin(hostPort: 'h:22', keyType: 'ssh-ed25519', sha256: 'AAA'),
      ],
    );
    final c = v.copyWith();
    expect(c.connections, same(v.connections));
    expect(c.folders, same(v.folders));
    expect(c.identities, same(v.identities));
    expect(c.pins, same(v.pins));
  });

  test('VaultData.copyWith replaces only the given field', () {
    const base = VaultData(
      connections: [], folders: [], identities: [], pins: [],
    );
    const newIdentity = Identity(id: 'i1', label: 'p',
        type: IdentityType.password, secret: 's', passphrase: null);
    final c = base.copyWith(identities: const [newIdentity]);
    expect(c.identities.single.id, 'i1');
    // Untouched fields keep their original (same) reference.
    expect(c.connections, same(base.connections));
    expect(c.folders, same(base.folders));
    expect(c.pins, same(base.pins));
  });

  test('VaultData.copyWith can replace several fields at once', () {
    const base = VaultData(
      connections: [], folders: [], identities: [], pins: [],
    );
    const conn = Connection(id: 'c1', label: 'box', host: 'h',
        folderId: null, username: 'u', port: 22, authRef: 'i1',
        tags: [], order: 0);
    const pin = HostKeyPin(hostPort: 'h:22', keyType: 'ssh-ed25519',
        sha256: 'AAA');
    final c = base.copyWith(connections: const [conn], pins: const [pin]);
    expect(c.connections.single.id, 'c1');
    expect(c.pins.single.sha256, 'AAA');
    expect(c.folders, same(base.folders));
    expect(c.identities, same(base.identities));
  });

  test('VaultData round-trips folders', () {
    const v = VaultData(
      connections: [],
      folders: [
        Folder(id: 'f1', parentId: null, name: 'work',
            username: 'deploy', port: null, authRef: 'i1', order: 0),
      ],
      identities: [],
      pins: [],
    );
    final r = VaultData.fromJson(v.toJson());
    expect(r.folders.single.name, 'work');
    expect(r.folders.single.username, 'deploy');
  });
}
