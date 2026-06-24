import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/keygen/key_generator.dart';

/// KeyGenerator.deriveFromPem must reproduce, from the stored private PEM alone,
/// the SAME non-secret public key + canonical fingerprint that generation
/// emitted (ADR 0033 / D1). The private key never leaks into the result.
void main() {
  final gen = KeyGenerator();

  /// The base64 body of an authorized_keys line ("<type> <base64> [comment]").
  String body(String line) => line.split(' ')[1];

  String type(String line) => line.split(' ')[0];

  test('Ed25519: derived public key + fingerprint match generation', () async {
    final key = await gen.generate(
      algorithm: KeyAlgorithm.ed25519,
      comment: 'me@host',
    );
    final info = KeyGenerator.deriveFromPem(key.privateKeyPem);
    expect(info, isNotNull);
    // Same algorithm prefix and same wire base64 — the public key is identical.
    expect(type(info!.publicKeyOpenSSH), 'ssh-ed25519');
    expect(body(info.publicKeyOpenSSH), body(key.publicKeyOpenSSH));
    // The fingerprint round-trips to the exact canonical value generation made.
    expect(info.fingerprint, key.fingerprint);
    expect(info.fingerprint, startsWith('SHA256:'));
    expect(info.fingerprint.contains('='), isFalse); // unpadded base64
  });

  test('RSA: derived public key + fingerprint match generation', () async {
    final key = await gen.generate(
      algorithm: KeyAlgorithm.rsa,
      rsaBits: 2048,
      comment: 'r@h',
    );
    final info = KeyGenerator.deriveFromPem(key.privateKeyPem);
    expect(info, isNotNull);
    expect(type(info!.publicKeyOpenSSH), 'ssh-rsa');
    expect(body(info.publicKeyOpenSSH), body(key.publicKeyOpenSSH));
    expect(info.fingerprint, key.fingerprint);
  });

  test('ECDSA: derived public key + fingerprint match generation', () async {
    final key = await gen.generate(
      algorithm: KeyAlgorithm.ecdsa,
      curve: EcdsaCurve.p256,
      comment: 'e@h',
    );
    final info = KeyGenerator.deriveFromPem(key.privateKeyPem);
    expect(info, isNotNull);
    expect(type(info!.publicKeyOpenSSH), 'ecdsa-sha2-nistp256');
    expect(body(info.publicKeyOpenSSH), body(key.publicKeyOpenSSH));
    expect(info.fingerprint, key.fingerprint);
  });

  test('corrupt/empty PEM returns null (no crash, no secret prompt)', () {
    expect(KeyGenerator.deriveFromPem(''), isNull);
    expect(KeyGenerator.deriveFromPem('not a pem'), isNull);
    expect(
      KeyGenerator.deriveFromPem(
        '-----BEGIN OPENSSH PRIVATE KEY-----\ngarbage\n-----END OPENSSH PRIVATE KEY-----',
      ),
      isNull,
    );
  });
}
