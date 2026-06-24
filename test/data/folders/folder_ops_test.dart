import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/folders/folder_ops.dart';

Connection _conn(String id, {String? folderId, int order = 0}) => Connection(
  id: id,
  label: id,
  host: 'h',
  folderId: folderId,
  username: null,
  port: null,
  authRef: null,
  tags: const [],
  order: order,
);

Folder _folder(String id, String? parentId, {int order = 0}) => Folder(
  id: id,
  parentId: parentId,
  name: id,
  username: null,
  port: null,
  authRef: null,
  order: order,
);

VaultData _vault({
  List<Folder> folders = const [],
  List<Connection> conns = const [],
}) => VaultData(
  connections: conns,
  folders: folders,
  identities: const [],
  pins: const [],
);

void main() {
  test('addFolder appends a folder', () {
    final v = addFolder(_vault(), id: 'f1', parentId: null, name: 'work');
    expect(v.folders.single.id, 'f1');
    expect(v.folders.single.name, 'work');
  });

  test('renameFolder changes only the target name', () {
    final v0 = _vault(folders: [_folder('f1', null), _folder('f2', null)]);
    final v = renameFolder(v0, 'f1', 'renamed');
    expect(v.folders.firstWhere((f) => f.id == 'f1').name, 'renamed');
    expect(v.folders.firstWhere((f) => f.id == 'f2').name, 'f2');
  });

  test('setFolderDefaults replaces the three inheritable fields', () {
    final v0 = _vault(folders: [_folder('f1', null)]);
    final v = setFolderDefaults(
      v0,
      'f1',
      username: 'deploy',
      port: 2222,
      authRef: 'i1',
    );
    final f = v.folders.single;
    expect(f.username, 'deploy');
    expect(f.port, 2222);
    expect(f.authRef, 'i1');
  });

  test('moveFolder re-parents; cyclic move is a no-op', () {
    final v0 = _vault(folders: [_folder('a', null), _folder('b', 'a')]);
    final moved = moveFolder(v0, 'b', null);
    expect(moved.folders.firstWhere((f) => f.id == 'b').parentId, isNull);
    // a under b would be a cycle -> unchanged
    final cyc = moveFolder(v0, 'a', 'b');
    expect(cyc.folders.firstWhere((f) => f.id == 'a').parentId, isNull);
  });

  test(
    'deleteFolderReparent moves child folders and connections to grandparent',
    () {
      final v0 = _vault(
        folders: [
          _folder('root', null),
          _folder('mid', 'root'),
          _folder('leaf', 'mid'),
        ],
        conns: [_conn('c1', folderId: 'mid')],
      );
      final v = deleteFolderReparent(v0, 'mid');
      expect(v.folders.any((f) => f.id == 'mid'), isFalse);
      expect(
        v.folders.firstWhere((f) => f.id == 'leaf').parentId,
        'root',
      ); // reparented
      expect(v.connections.single.folderId, 'root'); // reparented
    },
  );

  test('deleting a root folder reparents children to root (null)', () {
    final v0 = _vault(
      folders: [_folder('root', null), _folder('child', 'root')],
      conns: [_conn('c1', folderId: 'root')],
    );
    final v = deleteFolderReparent(v0, 'root');
    expect(v.folders.single.id, 'child');
    expect(v.folders.single.parentId, isNull);
    expect(v.connections.single.folderId, isNull);
  });

  group('reorderSiblings (ADR 0035 D1)', () {
    test('assigns dense 0..n-1 order in list order', () {
      final folders = [
        _folder('a', null),
        _folder('b', null),
        _folder('c', null),
      ];
      final out = reorderSiblings(folders, (f, i) => f.withOrder(i));
      expect(out.map((f) => f.order).toList(), [0, 1, 2]);
      expect(out.map((f) => f.id).toList(), ['a', 'b', 'c']);
    });

    test('empty group yields empty list', () {
      expect(
        reorderSiblings<Folder>(const [], (f, i) => f.withOrder(i)),
        isEmpty,
      );
    });
  });

  group('moveFolderOrdered (ADR 0035 D1)', () {
    test('re-parents AND renumbers the destination level gap-free', () {
      // dest 'root' has d0,d1; 'm' starts under 'src'.
      final v0 = _vault(
        folders: [
          _folder('d0', null, order: 0),
          _folder('d1', null, order: 1),
          _folder('src', null, order: 2),
          _folder('m', 'src', order: 0),
        ],
      );
      final v = moveFolderOrdered(v0, 'm', newParentId: null, order: 1);
      Folder by(String id) => v.folders.firstWhere((f) => f.id == id);
      expect(by('m').parentId, isNull);
      // Root level renumbered in visual order: d0, m, d1, src.
      expect(by('d0').order, 0);
      expect(by('m').order, 1);
      expect(by('d1').order, 2);
      expect(by('src').order, 3);
    });

    test('same-level reorder works through the same path', () {
      final v0 = _vault(
        folders: [
          _folder('a', null, order: 0),
          _folder('b', null, order: 1),
          _folder('c', null, order: 2),
        ],
      );
      // Move 'c' to the front of the root level.
      final v = moveFolderOrdered(v0, 'c', newParentId: null, order: 0);
      Folder by(String id) => v.folders.firstWhere((f) => f.id == id);
      expect(by('c').order, 0);
      expect(by('a').order, 1);
      expect(by('b').order, 2);
    });

    test('moving a folder into its own descendant is rejected (no-op)', () {
      final v0 = _vault(folders: [_folder('a', null), _folder('b', 'a')]);
      // 'a' into 'b' (its child) would create a cycle → unchanged.
      final v = moveFolderOrdered(v0, 'a', newParentId: 'b', order: 0);
      expect(v.folders.firstWhere((f) => f.id == 'a').parentId, isNull);
      expect(v, v0);
    });

    test('unknown folder id is a no-op', () {
      final v0 = _vault(folders: [_folder('a', null)]);
      expect(moveFolderOrdered(v0, 'missing', newParentId: null, order: 0), v0);
    });
  });

  group('create-order fix (ADR 0035 D1 — nextOrder, not fixed 0)', () {
    test(
      'appended siblings get increasing order so insertion order is kept',
      () {
        // Simulate the persist path: each new root host gets nextOrder of its
        // siblings instead of the old fixed 0.
        var conns = <Connection>[];
        Connection make(String id) => _conn(
          id,
          folderId: null,
          order: nextOrder(
            conns.where((c) => c.folderId == null).map((c) => c.order),
          ),
        );
        conns = [...conns, make('first')];
        conns = [...conns, make('second')];
        conns = [...conns, make('third')];
        expect(conns.firstWhere((c) => c.id == 'first').order, 0);
        expect(conns.firstWhere((c) => c.id == 'second').order, 1);
        expect(conns.firstWhere((c) => c.id == 'third').order, 2);
      },
    );
  });
}
