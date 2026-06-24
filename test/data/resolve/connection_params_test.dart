import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/data/resolve/connection_params.dart';

Connection _conn({
  String host = 'h.example',
  String? folderId,
  String? username,
  int? port,
  String? authRef,
}) =>
    Connection(
      id: 'c1', label: 'box', host: host,
      folderId: folderId, username: username, port: port, authRef: authRef,
      tags: const [], order: 0,
    );

Identity _id(String id, IdentityType type,
        {String secret = 's', String? passphrase}) =>
    Identity(id: id, label: id, type: type, secret: secret, passphrase: passphrase);

void main() {
  group('identityById', () {
    test('returns the matching identity', () {
      final ids = [
        _id('a', IdentityType.password),
        _id('b', IdentityType.privateKey),
      ];
      expect(identityById(ids, 'b')?.id, 'b');
    });

    test('returns null for a dangling/unknown id', () {
      expect(identityById([_id('a', IdentityType.password)], 'zzz'), isNull);
      expect(identityById(const [], 'a'), isNull);
    });
  });

  group('connectionById', () {
    test('returns the matching connection or null', () {
      final conns = [_conn(), const Connection(
        id: 'c2', label: 'b2', host: 'h2', folderId: null, username: null,
        port: null, authRef: null, tags: [], order: 0)];
      expect(connectionById(conns, 'c2')?.id, 'c2');
      expect(connectionById(conns, 'nope'), isNull);
      expect(connectionById(conns, null), isNull);
    });
  });

  group('paramsFor', () {
    test('builds password params from a resolved password identity', () {
      final conn = _conn(username: 'me', port: 2022, authRef: 'pw');
      final params = paramsFor(
        conn,
        folders: const [],
        identities: [_id('pw', IdentityType.password, secret: 'pass123')],
      );
      expect(params, isNotNull);
      expect(params!.host, 'h.example');
      expect(params.port, 2022);
      expect(params.username, 'me');
      expect(params.password, 'pass123');
      expect(params.privateKeyPem, isNull);
      expect(params.keyPassphrase, isNull);
    });

    test('builds key params from a resolved key identity (with passphrase)', () {
      final conn = _conn(username: 'me', authRef: 'k');
      final params = paramsFor(
        conn,
        folders: const [],
        identities: [
          _id('k', IdentityType.privateKey, secret: 'PEM', passphrase: 'pp')
        ],
      );
      expect(params!.privateKeyPem, 'PEM');
      expect(params.password, isNull);
      expect(params.keyPassphrase, 'pp');
      expect(params.port, 22); // resolver fallback
    });

    test('inherits username/authRef/port from the folder chain', () {
      final folders = [
        const Folder(id: 'f', parentId: null, name: 'f',
            username: 'deploy', port: 2222, authRef: 'k', order: 0),
      ];
      final conn = _conn(folderId: 'f');
      final params = paramsFor(
        conn,
        folders: folders,
        identities: [_id('k', IdentityType.privateKey, secret: 'PEM')],
      );
      expect(params!.username, 'deploy');
      expect(params.port, 2222);
      expect(params.privateKeyPem, 'PEM');
    });

    test('returns null when username is unresolved', () {
      final params = paramsFor(
        _conn(authRef: 'pw'),
        folders: const [],
        identities: [_id('pw', IdentityType.password)],
      );
      expect(params, isNull);
    });

    test('returns null when authRef is unresolved', () {
      final params = paramsFor(
        _conn(username: 'me'),
        folders: const [],
        identities: const [],
      );
      expect(params, isNull);
    });

    test('returns null for a dangling authRef (identity deleted)', () {
      final params = paramsFor(
        _conn(username: 'me', authRef: 'gone'),
        folders: const [],
        identities: [_id('other', IdentityType.password)],
      );
      expect(params, isNull);
    });
  });
}
