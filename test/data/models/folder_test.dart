import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/folder.dart';

void main() {
  test('Folder round-trips through JSON', () {
    const f = Folder(
      id: 'f1',
      parentId: 'root',
      name: 'work',
      username: 'deploy',
      port: 2222,
      authRef: 'i1',
      order: 3,
    );
    final r = Folder.fromJson(f.toJson());
    expect(r.id, 'f1');
    expect(r.parentId, 'root');
    expect(r.name, 'work');
    expect(r.username, 'deploy');
    expect(r.port, 2222);
    expect(r.authRef, 'i1');
    expect(r.order, 3);
  });

  test('Folder.fromJson defaults missing optional fields', () {
    final r = Folder.fromJson({'id': 'f1', 'name': 'root-folder'});
    expect(r.parentId, isNull);
    expect(r.username, isNull);
    expect(r.port, isNull);
    expect(r.authRef, isNull);
    expect(r.order, 0);
  });

  test('withParent / rename / withDefaults return updated copies', () {
    const f = Folder(
        id: 'f1', parentId: null, name: 'a',
        username: 'u', port: 22, authRef: 'i1', order: 0);
    expect(f.withParent('p2').parentId, 'p2');
    expect(f.withParent(null).parentId, isNull);
    expect(f.rename('b').name, 'b');
    final cleared = f.withDefaults(username: null, port: null, authRef: null);
    expect(cleared.username, isNull);
    expect(cleared.port, isNull);
    expect(cleared.authRef, isNull);
    // unrelated fields preserved
    expect(cleared.id, 'f1');
    expect(cleared.name, 'a');
  });
}
