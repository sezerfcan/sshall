import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/crypto/crypto_service.dart';

void main() {
  final crypto = CryptoService();

  test('Argon2id derivation is deterministic for same password+salt', () async {
    final pw = Uint8List.fromList('correct horse'.codeUnits);
    final salt = Uint8List.fromList(List.generate(16, (i) => i));
    final a = await crypto.deriveKek(pw, salt);
    final b = await crypto.deriveKek(pw, salt);
    expect(a.length, 32);
    expect(a, equals(b));
  });

  test('AEAD round-trips and rejects a tampered blob', () async {
    final key = crypto.randomBytes(32);
    final msg = Uint8List.fromList('vault payload çöğ'.codeUnits);
    final blob = await crypto.aeadEncrypt(key, msg);
    expect(await crypto.aeadDecrypt(key, blob), equals(msg));

    final tampered = Uint8List.fromList(blob)..[blob.length - 1] ^= 0xff;
    expect(await crypto.aeadDecrypt(key, tampered), isNull);

    final wrongKey = crypto.randomBytes(32);
    expect(await crypto.aeadDecrypt(wrongKey, blob), isNull);
  });
}
