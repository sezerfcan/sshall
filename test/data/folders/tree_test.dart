import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/folders/tree.dart';

Connection _conn(String id, {String? folderId, int order = 0}) => Connection(
    id: id, label: id, host: 'h', folderId: folderId,
    username: null, port: null, authRef: null, tags: const [], order: order);

Folder _folder(String id, String? parentId, {int order = 0}) => Folder(
    id: id, parentId: parentId, name: id,
    username: null, port: null, authRef: null, order: order);

void main() {
  test('expanded tree is depth-first with correct depths', () {
    final folders = [_folder('work', null), _folder('prod', 'work')];
    final conns = [_conn('web', folderId: 'prod'), _conn('laptop', folderId: null)];
    final rows = buildTreeRows(folders, conns, {'work', 'prod'});
    final ids = rows.map((r) => r.isFolder ? r.folder!.id : r.connection!.id).toList();
    expect(ids, ['work', 'prod', 'web', 'laptop']);
    final webRow = rows.firstWhere((r) => r.connection?.id == 'web');
    expect(webRow.depth, 2);
  });

  test('collapsed folder hides its subtree', () {
    final folders = [_folder('work', null), _folder('prod', 'work')];
    final conns = [_conn('web', folderId: 'prod')];
    final rows = buildTreeRows(folders, conns, <String>{}); // nothing expanded
    final ids = rows.map((r) => r.isFolder ? r.folder!.id : r.connection!.id).toList();
    expect(ids, ['work']); // prod + web hidden
  });

  test('siblings are ordered by order then name', () {
    final folders = [_folder('b', null, order: 1), _folder('a', null, order: 0)];
    final rows = buildTreeRows(folders, const [], <String>{});
    expect(rows.map((r) => r.folder!.id).toList(), ['a', 'b']);
  });

  test('filterTree keeps matching hosts and their ancestor folders', () {
    final folders = [_folder('work', null), _folder('prod', 'work')];
    final conns = [
      _conn('web', folderId: 'prod'), // label == id == 'web'
      _conn('laptop', folderId: null),
    ];
    final res = filterTree(folders, conns, 'web');
    expect(res.conns.map((c) => c.id), ['web']);
    // ancestors of 'web' (prod, work) retained; unrelated none
    expect(res.folders.map((f) => f.id).toSet(), {'work', 'prod'});
  });

  test('filterTree matches tags and is case-insensitive', () {
    final conns = [
      const Connection(id: 'db', label: 'db', host: 'h', folderId: null,
          username: null, port: null, authRef: null,
          tags: ['Production'], order: 0),
    ];
    final res = filterTree(const [], conns, 'production');
    expect(res.conns.single.id, 'db');
  });

  test('empty query returns everything', () {
    final folders = [_folder('a', null)];
    final conns = [_conn('x', folderId: null)];
    final res = filterTree(folders, conns, '   ');
    expect(res.folders.length, 1);
    expect(res.conns.length, 1);
  });

  test('filterTree matches a username inherited from the folder', () {
    final folders = [
      const Folder(id: 'work', parentId: null, name: 'work',
          username: 'deploy', port: null, authRef: null, order: 0),
    ];
    final conns = [
      // No own username ⇒ 'deploy' is only reachable via inheritance.
      _conn('web', folderId: 'work'),
    ];
    final res = filterTree(folders, conns, 'deploy');
    expect(res.conns.map((c) => c.id), ['web']);
    expect(res.folders.map((f) => f.id).toSet(), {'work'});
  });

  test('filterTree matches a connection own username', () {
    final conns = [
      const Connection(id: 'box', label: 'box', host: 'h', folderId: null,
          username: 'root', port: null, authRef: null, tags: [], order: 0),
    ];
    final res = filterTree(const [], conns, 'root');
    expect(res.conns.single.id, 'box');
  });
}
