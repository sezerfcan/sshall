import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/keygen/key_generator.dart';

void main() {
  final gen = KeyGenerator();

  // The public key embedded in a generated key's OpenSSH line, re-derived from
  // the private PEM by dartssh2 (the SAME parser the SSH layer uses). Equality
  // proves the key is internally consistent and usable for authentication.
  String reparsedPublicB64(GeneratedKey key) {
    final pair = SSHKeyPair.fromPem(key.privateKeyPem).first;
    return base64.encode(pair.toPublicKey().encode());
  }

  String emittedPublicB64(GeneratedKey key) => key.publicKeyOpenSSH.split(' ')[1];

  group('Ed25519', () {
    test('round-trips through SSHKeyPair.fromPem', () async {
      final key = await gen.generate(
          algorithm: KeyAlgorithm.ed25519, comment: 'test@sshall');

      expect(() => SSHKeyPair.fromPem(key.privateKeyPem), returnsNormally);
      expect(reparsedPublicB64(key), emittedPublicB64(key));
    });

    test('public key line + fingerprint are well-formed', () async {
      final key = await gen.generate(
          algorithm: KeyAlgorithm.ed25519, comment: 'me@host');

      expect(key.algorithm, KeyAlgorithm.ed25519);
      expect(key.publicKeyOpenSSH, startsWith('ssh-ed25519 '));
      expect(key.publicKeyOpenSSH, endsWith(' me@host'));
      expect(key.fingerprint, startsWith('SHA256:'));
      expect(key.privateKeyPem, contains('OPENSSH PRIVATE KEY'));
    });

    test('produces a distinct key each call', () async {
      final a = await gen.generate(algorithm: KeyAlgorithm.ed25519, comment: 'c');
      final b = await gen.generate(algorithm: KeyAlgorithm.ed25519, comment: 'c');
      expect(a.privateKeyPem, isNot(b.privateKeyPem));
    });
  });

  group('ECDSA', () {
    for (final entry in const {
      EcdsaCurve.p256: 'ecdsa-sha2-nistp256',
      EcdsaCurve.p384: 'ecdsa-sha2-nistp384',
      EcdsaCurve.p521: 'ecdsa-sha2-nistp521',
    }.entries) {
      test('${entry.key} round-trips and has the right type', () async {
        final key = await gen.generate(
            algorithm: KeyAlgorithm.ecdsa, curve: entry.key, comment: 'e@h');

        expect(() => SSHKeyPair.fromPem(key.privateKeyPem), returnsNormally);
        expect(reparsedPublicB64(key), emittedPublicB64(key));
        expect(key.publicKeyOpenSSH, startsWith('${entry.value} '));
        expect(key.fingerprint, startsWith('SHA256:'));
      });
    }
  });

  group('RSA', () {
    test('2048-bit round-trips and is ssh-rsa', () async {
      final key = await gen.generate(
          algorithm: KeyAlgorithm.rsa, rsaBits: 2048, comment: 'r@h');

      expect(() => SSHKeyPair.fromPem(key.privateKeyPem), returnsNormally);
      expect(reparsedPublicB64(key), emittedPublicB64(key));
      expect(key.publicKeyOpenSSH, startsWith('ssh-rsa '));
      expect(key.fingerprint, startsWith('SHA256:'));
    });
  });
}
