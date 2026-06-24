// test/data/models/connection_docker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';

Connection base() => const Connection(
      id: 'c1', label: 'h', host: 'h', folderId: null, username: null,
      port: null, authRef: null, tags: [], order: 0,
    );

void main() {
  test('docker defaults to false and dockerBinary to null', () {
    final c = base();
    expect(c.docker, isFalse);
    expect(c.dockerBinary, isNull);
  });

  test('docker fields round-trip through json', () {
    final c = base().copyWith(docker: true, dockerBinary: 'sudo docker');
    final back = Connection.fromJson(c.toJson());
    expect(back.docker, isTrue);
    expect(back.dockerBinary, 'sudo docker');
  });

  test('fromJson tolerates legacy records without docker fields', () {
    final legacy = {
      'id': 'c1', 'label': 'h', 'host': 'h', 'folderId': null,
      'username': null, 'port': null, 'authRef': null, 'tags': [], 'order': 0,
    };
    final c = Connection.fromJson(legacy);
    expect(c.docker, isFalse);
    expect(c.dockerBinary, isNull);
  });

  test('copyWith can clear dockerBinary back to null', () {
    final c = base().copyWith(dockerBinary: 'docker');
    final cleared = c.copyWith(dockerBinary: null);
    expect(cleared.dockerBinary, isNull);
  });
}
