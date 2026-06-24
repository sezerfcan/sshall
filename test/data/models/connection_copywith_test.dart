import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';

Connection _c() => const Connection(
    id: 'c1', label: 'web', host: 'h', folderId: 'f1',
    username: 'root', port: 22, authRef: 'i1', tags: ['p'], order: 3);

void main() {
  test('copyWith with no args returns an equal-valued copy', () {
    final c = _c().copyWith();
    expect(c.id, 'c1');
    expect(c.label, 'web');
    expect(c.host, 'h');
    expect(c.folderId, 'f1');
    expect(c.username, 'root');
    expect(c.port, 22);
    expect(c.authRef, 'i1');
    expect(c.tags, ['p']);
    expect(c.order, 3);
  });

  test('copyWith sets non-null overrides', () {
    final c = _c().copyWith(label: 'db', host: 'h2', username: 'deploy', port: 2222);
    expect(c.label, 'db');
    expect(c.host, 'h2');
    expect(c.username, 'deploy');
    expect(c.port, 2222);
    expect(c.authRef, 'i1'); // untouched
  });

  test('copyWith explicit null clears nullable fields (inherit)', () {
    final c = _c().copyWith(folderId: null, username: null, port: null, authRef: null);
    expect(c.folderId, isNull);
    expect(c.username, isNull);
    expect(c.port, isNull);
    expect(c.authRef, isNull);
    expect(c.label, 'web'); // untouched
  });

  test('omitting a nullable field keeps it (sentinel)', () {
    final c = _c().copyWith(label: 'x');
    expect(c.username, 'root');
    expect(c.port, 22);
    expect(c.authRef, 'i1');
    expect(c.folderId, 'f1');
  });
}
