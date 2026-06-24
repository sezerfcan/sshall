import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/features/vault/identity_filter.dart';
import 'package:sshall/features/vault/identity_view_model.dart';

Identity _key(String id, {String label = 'k', String? fp, String? pub}) =>
    Identity(
      id: id,
      label: label,
      type: IdentityType.privateKey,
      secret: 's',
      passphrase: null,
      publicKeyOpenSSH: pub ?? 'ssh-ed25519 AAAA c',
      fingerprint: fp ?? 'SHA256:$id',
    );

Identity _pw(String id, {String label = 'pw'}) => Identity(
  id: id,
  label: label,
  type: IdentityType.password,
  secret: 's',
  passphrase: null,
);

IdentityView _viewOf(Identity i) => IdentityView.of(i, deriver: (_) => null);

List<Identity> _filter(
  List<Identity> all, {
  String query = '',
  IdentityTypeFilter type = IdentityTypeFilter.all,
  bool unusedOnly = false,
  Map<String, int> usage = const {},
}) => filterIdentities(
  all,
  query: query,
  typeFilter: type,
  unusedOnly: unusedOnly,
  usage: usage,
  viewOf: _viewOf,
);

void main() {
  test('empty query returns everything', () {
    final all = [_key('a'), _pw('b')];
    expect(_filter(all).length, 2);
  });

  test('query matches the label substring', () {
    final all = [_key('a', label: 'prod-server'), _key('b', label: 'staging')];
    final out = _filter(all, query: 'prod');
    expect(out.map((i) => i.id), ['a']);
  });

  test('query matches the algorithm label', () {
    final all = [
      _key('a', pub: 'ssh-ed25519 AAAA c'),
      _key('b', pub: 'ssh-rsa AAAAB3NzaC1yc2E c'),
    ];
    final out = _filter(all, query: 'ed25519');
    expect(out.map((i) => i.id), ['a']);
  });

  test('query matches a pasted server SHA256 fingerprint', () {
    final all = [
      _key('a', fp: 'SHA256:ZZZZserverkey'),
      _key('b', fp: 'SHA256:other'),
    ];
    // User pastes the server-reported fingerprint → finds the local key.
    final out = _filter(all, query: 'SHA256:ZZZZserverkey');
    expect(out.map((i) => i.id), ['a']);
  });

  test('type filter splits keys and passwords', () {
    final all = [_key('a'), _pw('b')];
    expect(_filter(all, type: IdentityTypeFilter.keys).map((i) => i.id), ['a']);
    expect(_filter(all, type: IdentityTypeFilter.passwords).map((i) => i.id), [
      'b',
    ]);
  });

  test('unusedOnly keeps only zero-usage identities', () {
    final all = [_key('a'), _key('b')];
    final out = _filter(all, unusedOnly: true, usage: {'a': 2});
    expect(out.map((i) => i.id), ['b']);
  });

  test('filters compose (type + query + unused)', () {
    final all = [
      _key('a', label: 'prod'),
      _key('b', label: 'prod-old'),
      _pw('c', label: 'prod-pw'),
    ];
    final out = _filter(
      all,
      query: 'prod',
      type: IdentityTypeFilter.keys,
      unusedOnly: true,
      usage: {'a': 1},
    );
    expect(out.map((i) => i.id), ['b']);
  });
}
