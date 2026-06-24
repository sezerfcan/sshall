import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' show SigningKey;
import 'package:pointycastle/export.dart';
// ignore: implementation_imports
import 'package:dartssh2/src/ssh_key_pair.dart';

enum KeyAlgorithm { ed25519, ecdsa, rsa }

enum EcdsaCurve { p256, p384, p521 }

/// Result of a key generation. All fields are plain data so the object can be
/// returned across an isolate boundary. The private key is never displayed
/// (ADR 0005); it is stored only inside the encrypted vault.
class GeneratedKey {
  final KeyAlgorithm algorithm;

  /// "-----BEGIN OPENSSH PRIVATE KEY-----..." — unencrypted; the vault is the
  /// at-rest protection (ADR 0005).
  final String privateKeyPem;

  /// authorized_keys line: "<type> <base64> <comment>".
  final String publicKeyOpenSSH;

  /// "SHA256:<base64-without-padding>".
  final String fingerprint;

  const GeneratedKey({
    required this.algorithm,
    required this.privateKeyPem,
    required this.publicKeyOpenSSH,
    required this.fingerprint,
  });
}

/// The NON-SECRET public material derivable from a stored private key (ADR 0033
/// / D1). The private key + passphrase are never part of this result.
class PublicKeyInfo {
  /// One-line authorized_keys format: "<type> <base64> <comment>".
  final String publicKeyOpenSSH;

  /// Canonical "SHA256:<base64-without-padding>" — identical format to what
  /// [GeneratedKey.fingerprint] produces, so a derived value compares equal.
  final String fingerprint;

  const PublicKeyInfo({
    required this.publicKeyOpenSSH,
    required this.fingerprint,
  });
}

/// Generates SSH key pairs (ADR 0012). Reuses dartssh2's concrete OpenSSH
/// keypair classes so the emitted PEM is guaranteed to re-parse through
/// SSHKeyPair.fromPem — the same path the SSH layer uses to authenticate.
class KeyGenerator {
  /// Runs the CPU-heavy work off the UI isolate (RSA-4096 can take seconds).
  Future<GeneratedKey> generate({
    required KeyAlgorithm algorithm,
    EcdsaCurve curve = EcdsaCurve.p256,
    int rsaBits = 4096,
    required String comment,
  }) {
    return Isolate.run(() => _generateSync(algorithm, curve, rsaBits, comment));
  }

  /// Derives the NON-SECRET public key line + SHA256 fingerprint from a stored
  /// private-key PEM (ADR 0033 / D1). Used for legacy/imported identities that
  /// predate persisted public material. The result reuses the SAME canonical
  /// format the generator emits, so a derived fingerprint round-trips equal.
  ///
  /// Returns null when the PEM cannot be parsed (encrypted/corrupt/empty). The
  /// passphrase is accepted only to unlock an encrypted PEM for the derivation;
  /// it is NEVER stored or surfaced. The private key never leaves this method.
  static PublicKeyInfo? deriveFromPem(String pem, {String? passphrase}) {
    try {
      final pairs = SSHKeyPair.fromPem(pem, passphrase);
      if (pairs.isEmpty) return null;
      final pair = pairs.first;
      final wire = pair.toPublicKey().encode();
      // The OpenSSH key-type prefix (e.g. "ssh-ed25519") is the first
      // length-prefixed string in the wire encoding. Read it so the emitted
      // authorized_keys line carries the correct type without re-deriving it.
      final keyType = _readWireString(wire);
      return PublicKeyInfo(
        publicKeyOpenSSH: '$keyType ${base64.encode(wire)}',
        fingerprint: _sha256Fingerprint(wire),
      );
    } catch (_) {
      // Encrypted-without-passphrase, malformed, or unsupported PEM: surface
      // null so the UI can fall back gracefully without ever prompting for /
      // exposing a secret.
      return null;
    }
  }
}

/// Reads the first SSH wire string ("string" = uint32 length + bytes) from a
/// public-key blob; this is the algorithm name (e.g. "ssh-ed25519").
String _readWireString(Uint8List wire) {
  final len = (wire[0] << 24) | (wire[1] << 16) | (wire[2] << 8) | wire[3];
  return utf8.decode(wire.sublist(4, 4 + len));
}

GeneratedKey _generateSync(
  KeyAlgorithm algorithm,
  EcdsaCurve curve,
  int rsaBits,
  String comment,
) {
  switch (algorithm) {
    case KeyAlgorithm.ed25519:
      final sk = SigningKey.generate();
      final publicKey = Uint8List.fromList(sk.verifyKey); // 32 bytes
      final privateKey = Uint8List.fromList(sk); // 64 bytes: seed || public
      final kp = OpenSSHEd25519KeyPair(publicKey, privateKey, comment);
      return _finish(KeyAlgorithm.ed25519, kp, 'ssh-ed25519', comment);
    case KeyAlgorithm.ecdsa:
      final domain = switch (curve) {
        EcdsaCurve.p256 => ECCurve_secp256r1(),
        EcdsaCurve.p384 => ECCurve_secp384r1(),
        EcdsaCurve.p521 => ECCurve_secp521r1(),
      };
      final curveId = switch (curve) {
        EcdsaCurve.p256 => 'nistp256',
        EcdsaCurve.p384 => 'nistp384',
        EcdsaCurve.p521 => 'nistp521',
      };
      final ecGen = ECKeyGenerator()
        ..init(
          ParametersWithRandom(
            ECKeyGeneratorParameters(domain),
            _secureRandom(),
          ),
        );
      final pair = ecGen.generateKeyPair();
      final pub = pair.publicKey;
      final priv = pair.privateKey;
      final q = pub.Q!.getEncoded(false); // uncompressed: 0x04 || X || Y
      final kp = OpenSSHEcdsaKeyPair(curveId, q, priv.d!, comment);
      return _finish(KeyAlgorithm.ecdsa, kp, 'ecdsa-sha2-$curveId', comment);
    case KeyAlgorithm.rsa:
      final rsaGen = RSAKeyGenerator()
        ..init(
          ParametersWithRandom(
            RSAKeyGeneratorParameters(BigInt.from(65537), rsaBits, 64),
            _secureRandom(),
          ),
        );
      final pair = rsaGen.generateKeyPair();
      final pub = pair.publicKey;
      final priv = pair.privateKey;
      final n = pub.modulus!;
      final e = pub.exponent!;
      final d = priv.privateExponent!;
      final p = priv.p!;
      final q = priv.q!;
      final iqmp = q.modInverse(p);
      final kp = OpenSSHRsaKeyPair(n, e, d, iqmp, p, q, comment);
      return _finish(KeyAlgorithm.rsa, kp, 'ssh-rsa', comment);
  }
}

// All three concrete keypair classes mix in OpenSSHKeyPair, so this is fully
// typed — toPem() and toPublicKey() come from that mixin / SSHKeyPair.
GeneratedKey _finish(
  KeyAlgorithm algorithm,
  OpenSSHKeyPair kp,
  String keyType,
  String comment,
) {
  final wire = kp.toPublicKey().encode();
  return GeneratedKey(
    algorithm: algorithm,
    privateKeyPem: kp.toPem(),
    publicKeyOpenSSH: '$keyType ${base64.encode(wire)} $comment',
    fingerprint: _sha256Fingerprint(wire),
  );
}

String _sha256Fingerprint(Uint8List wire) {
  final digest = SHA256Digest().process(wire);
  return 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
}

SecureRandom _secureRandom() {
  final rnd = Random.secure();
  final seed = Uint8List(32);
  for (var i = 0; i < seed.length; i++) {
    seed[i] = rnd.nextInt(256);
  }
  return FortunaRandom()..seed(KeyParameter(seed));
}
