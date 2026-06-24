import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/identity.dart';
import 'package:sshall/features/vault/identity_view_model.dart';
import 'package:sshall/services/keygen/key_generator.dart';

void main() {
  group('IdentityView.of (ADR 0033 / D1, D2)', () {
    test('uses persisted public key + fingerprint without re-deriving', () {
      const id = Identity(
        id: 'i1',
        label: 'k',
        type: IdentityType.privateKey,
        secret: 'PEM-WOULD-FAIL-TO-PARSE',
        passphrase: null,
        publicKeyOpenSSH: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 c',
        fingerprint: 'SHA256:STORED',
      );
      var derived = false;
      final view = IdentityView.of(
        id,
        deriver: (_) {
          derived = true;
          return null;
        },
      );
      expect(derived, isFalse, reason: 'persisted values must short-circuit');
      expect(view.fingerprint, 'SHA256:STORED');
      expect(view.algorithmLabel, 'ED25519');
    });

    test('legacy key (no persisted fields) derives from the PEM', () async {
      final key = await KeyGenerator().generate(
        algorithm: KeyAlgorithm.ed25519,
        comment: 'c',
      );
      final legacy = Identity(
        id: 'i1',
        label: 'legacy',
        type: IdentityType.privateKey,
        secret: key.privateKeyPem,
        passphrase: null,
        // no publicKeyOpenSSH / fingerprint — imported before ADR 0033
      );
      final view = IdentityView.of(legacy);
      expect(view.fingerprint, key.fingerprint);
      expect(view.publicKeyOpenSSH, isNotNull);
      expect(view.algorithmLabel, 'ED25519');
    });

    test('RSA algorithm label includes the bit size', () async {
      final key = await KeyGenerator().generate(
        algorithm: KeyAlgorithm.rsa,
        rsaBits: 2048,
        comment: 'c',
      );
      final id = Identity(
        id: 'i1',
        label: 'rsa',
        type: IdentityType.privateKey,
        secret: key.privateKeyPem,
        passphrase: null,
        publicKeyOpenSSH: key.publicKeyOpenSSH,
        fingerprint: key.fingerprint,
      );
      expect(IdentityView.of(id).algorithmLabel, 'RSA 2048');
    });

    test('ECDSA algorithm label includes the curve', () async {
      final key = await KeyGenerator().generate(
        algorithm: KeyAlgorithm.ecdsa,
        curve: EcdsaCurve.p384,
        comment: 'c',
      );
      final id = Identity(
        id: 'i1',
        label: 'ec',
        type: IdentityType.privateKey,
        secret: key.privateKeyPem,
        passphrase: null,
        publicKeyOpenSSH: key.publicKeyOpenSSH,
        fingerprint: key.fingerprint,
      );
      expect(IdentityView.of(id).algorithmLabel, 'ECDSA nistp384');
    });

    test('password identity has no fingerprint and a "Parola" label', () {
      const id = Identity(
        id: 'i1',
        label: 'pw',
        type: IdentityType.password,
        secret: 'hunter2',
        passphrase: null,
      );
      final view = IdentityView.of(id);
      expect(view.fingerprint, isNull);
      expect(view.hasFingerprint, isFalse);
      expect(view.publicKeyOpenSSH, isNull);
      expect(view.algorithmLabel, 'Parola');
    });

    test('underivable key (encrypted/corrupt PEM) falls back to "Anahtar"', () {
      const id = Identity(
        id: 'i1',
        label: 'enc',
        type: IdentityType.privateKey,
        secret: 'garbage-pem',
        passphrase: null,
      );
      final view = IdentityView.of(id);
      expect(view.fingerprint, isNull);
      expect(view.algorithmLabel, 'Anahtar');
    });
  });
}
