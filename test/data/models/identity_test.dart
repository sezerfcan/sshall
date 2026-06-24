import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/identity.dart';

void main() {
  group('Identity NON-SECRET fields (ADR 0033 / D1)', () {
    test('toJson/fromJson round-trips the new fields', () {
      const id = Identity(
        id: 'i1',
        label: 'prod',
        type: IdentityType.privateKey,
        secret: 'PEM',
        passphrase: null,
        publicKeyOpenSSH: 'ssh-ed25519 AAAAB3 c',
        fingerprint: 'SHA256:abc123',
        createdAt: 1700000000000,
      );
      final back = Identity.fromJson(id.toJson());
      expect(back.publicKeyOpenSSH, 'ssh-ed25519 AAAAB3 c');
      expect(back.fingerprint, 'SHA256:abc123');
      expect(back.createdAt, 1700000000000);
      expect(back.secret, 'PEM');
    });

    test(
      'fromJson tolerates old records missing the new fields (back-compat)',
      () {
        // A vault written before ADR 0033 has no publicKeyOpenSSH/fingerprint/createdAt.
        final old = <String, dynamic>{
          'id': 'i1',
          'label': 'legacy',
          'type': 'privateKey',
          'secret': 'PEM',
          'passphrase': null,
        };
        final id = Identity.fromJson(old);
        expect(id.publicKeyOpenSSH, isNull);
        expect(id.fingerprint, isNull);
        expect(id.createdAt, isNull);
        expect(id.secret, 'PEM');
      },
    );

    test('toJson omits null non-secret keys (lean back-compat output)', () {
      const id = Identity(
        id: 'i1',
        label: 'legacy',
        type: IdentityType.password,
        secret: 's',
        passphrase: null,
      );
      final j = id.toJson();
      expect(j.containsKey('publicKeyOpenSSH'), isFalse);
      expect(j.containsKey('fingerprint'), isFalse);
      expect(j.containsKey('createdAt'), isFalse);
    });

    test(
      'copyWith(label:) changes only the label; secret/fingerprint kept',
      () {
        const id = Identity(
          id: 'i1',
          label: 'old',
          type: IdentityType.privateKey,
          secret: 'PEM',
          passphrase: 'phrase',
          publicKeyOpenSSH: 'ssh-rsa AAAA c',
          fingerprint: 'SHA256:xyz',
          createdAt: 123,
        );
        final renamed = id.copyWith(label: 'new');
        expect(renamed.label, 'new');
        expect(renamed.id, 'i1');
        expect(renamed.secret, 'PEM');
        expect(renamed.passphrase, 'phrase');
        expect(renamed.fingerprint, 'SHA256:xyz');
        expect(renamed.publicKeyOpenSSH, 'ssh-rsa AAAA c');
        expect(renamed.createdAt, 123);
      },
    );

    test(
      'copyWith can fill non-secret fields (generation/derivation path)',
      () {
        const id = Identity(
          id: 'i1',
          label: 'k',
          type: IdentityType.privateKey,
          secret: 'PEM',
          passphrase: null,
        );
        final filled = id.copyWith(
          publicKeyOpenSSH: 'ssh-ed25519 AAAA',
          fingerprint: 'SHA256:abc',
          createdAt: 999,
        );
        expect(filled.publicKeyOpenSSH, 'ssh-ed25519 AAAA');
        expect(filled.fingerprint, 'SHA256:abc');
        expect(filled.createdAt, 999);
      },
    );
  });
}
