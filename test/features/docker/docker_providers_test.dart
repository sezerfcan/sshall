import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/features/docker/docker_providers.dart';
import 'package:sshall/services/docker/ssh_docker_host.dart';

Connection _conn(
  String id, {
  bool docker = false,
  String? username = 'root',
  String? authRef = 'idA',
  String? dockerBinary,
}) =>
    Connection(
      id: id,
      label: id,
      host: 'h.example',
      folderId: null,
      username: username,
      port: 22,
      authRef: authRef,
      tags: const [],
      order: 0,
      docker: docker,
      dockerBinary: dockerBinary,
    );

Identity _idA() => const Identity(
      id: 'idA',
      label: 'pw',
      type: IdentityType.password,
      secret: 's3cret',
      passphrase: null,
    );

VaultData _data(List<Connection> conns, {List<Identity>? ids}) => VaultData(
      connections: conns,
      folders: const <Folder>[],
      identities: ids ?? [_idA()],
      pins: const [],
    );

void main() {
  group('dockerHostForConnection', () {
    test('returns null when the connection is missing', () {
      final data = _data([_conn('c1', docker: true)]);
      expect(dockerHostForConnection(data, 'nope'), isNull);
    });

    test('returns null when the connection is not a docker host', () {
      final data = _data([_conn('c1', docker: false)]);
      expect(dockerHostForConnection(data, 'c1'), isNull);
    });

    test('returns null when params are unresolvable (no username)', () {
      final data = _data([_conn('c1', docker: true, username: null)]);
      expect(dockerHostForConnection(data, 'c1'), isNull);
    });

    test('returns null when authRef points at a deleted identity', () {
      final data = _data([_conn('c1', docker: true, authRef: 'gone')]);
      expect(dockerHostForConnection(data, 'c1'), isNull);
    });

    test('returns a host for a resolved docker connection', () {
      final data = _data([_conn('c1', docker: true)]);
      final host = dockerHostForConnection(data, 'c1');
      expect(host, isA<SshDockerHost>());
    });

    test('honours a custom dockerBinary override', () {
      final data = _data([
        _conn('c1', docker: true, dockerBinary: 'sudo docker'),
      ]);
      final host = dockerHostForConnection(data, 'c1');
      expect(host, isA<SshDockerHost>());
    });
  });
}
