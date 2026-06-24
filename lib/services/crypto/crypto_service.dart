import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

/// KDF + AEAD primitives for the vault (ADR 0005).
class CryptoService {
  static const int kekLength = 32;
  static const int _nonceLength = 24; // XChaCha20
  static const int _macLength = 16; // Poly1305

  final _cipher = Xchacha20.poly1305Aead();
  final _random = Random.secure();

  /// Argon2id (RFC 9106 2nd profile). CPU/memory-heavy → run off the UI isolate.
  Future<Uint8List> deriveKek(Uint8List password, Uint8List salt) {
    return Isolate.run(() async {
      final argon2 = Argon2id(
        memory: 65536, // 64 MiB (KiB units)
        iterations: 3,
        parallelism: 4,
        hashLength: kekLength,
      );
      final key = await argon2.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  Uint8List randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// Returns nonce || ciphertext || mac.
  Future<Uint8List> aeadEncrypt(Uint8List key, Uint8List plaintext) async {
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Returns plaintext, or null if authentication fails.
  Future<Uint8List?> aeadDecrypt(Uint8List key, Uint8List blob) async {
    try {
      final box = SecretBox.fromConcatenation(
        blob,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _cipher.decrypt(box, secretKey: SecretKey(key));
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      // Structurally invalid blob (e.g. too short for nonce+mac) -> undecryptable.
      return null;
    }
  }
}
