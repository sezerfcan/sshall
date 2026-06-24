import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/resolve/connection_resolver.dart';

Connection _conn({
  String? folderId,
  String? username,
  int? port,
  String? authRef,
}) =>
    Connection(
      id: 'c1', label: 'box', host: 'h',
      folderId: folderId, username: username, port: port, authRef: authRef,
      tags: const [], order: 0,
    );

Folder _folder(String id, String? parentId,
        {String? username, int? port, String? authRef}) =>
    Folder(id: id, parentId: parentId, name: id,
        username: username, port: port, authRef: authRef, order: 0);

void main() {
  test('explicit connection values win over folder defaults', () {
    final folders = [_folder('f1', null, username: 'deploy', port: 2222, authRef: 'iF')];
    final r = resolve(
        _conn(folderId: 'f1', username: 'me', port: 22, authRef: 'iC'), folders);
    expect(r.username, 'me');
    expect(r.port, 22);
    expect(r.authRef, 'iC');
  });

  test('nearest folder wins across a multi-level chain', () {
    final folders = [
      _folder('root', null, username: 'rootuser', authRef: 'iRoot'),
      _folder('mid', 'root', username: 'miduser'),
      _folder('leaf', 'mid'),
    ];
    // connection in leaf inherits username from mid (nearest), authRef from root.
    final r = resolve(_conn(folderId: 'leaf'), folders);
    expect(r.username, 'miduser');
    expect(r.authRef, 'iRoot');
  });

  test('port falls back to 22 when nothing in the chain sets it', () {
    final folders = [_folder('f1', null, username: 'u', authRef: 'i')];
    final r = resolve(_conn(folderId: 'f1'), folders);
    expect(r.port, 22);
  });

  test('unresolved username/authRef stay null (caller blocks connect)', () {
    final r = resolve(_conn(folderId: null), const []);
    expect(r.username, isNull);
    expect(r.authRef, isNull);
    expect(r.port, 22);
  });

  test('chain walk terminates on a cyclic parent pointer', () {
    final folders = [
      _folder('a', 'b', username: 'ua'),
      _folder('b', 'a'),
    ];
    final r = resolve(_conn(folderId: 'a'), folders);
    expect(r.username, 'ua'); // does not hang
  });

  group('wouldCreateCycle', () {
    final folders = [
      _folder('root', null),
      _folder('child', 'root'),
      _folder('grand', 'child'),
    ];
    test('moving a folder under its own descendant is a cycle', () {
      expect(wouldCreateCycle('root', 'grand', folders), isTrue);
    });
    test('moving under itself is a cycle', () {
      expect(wouldCreateCycle('child', 'child', folders), isTrue);
    });
    test('moving to root (null) is never a cycle', () {
      expect(wouldCreateCycle('child', null, folders), isFalse);
    });
    test('moving to an unrelated branch is allowed', () {
      final f2 = [...folders, _folder('other', null)];
      expect(wouldCreateCycle('child', 'other', f2), isFalse);
    });
  });
}
