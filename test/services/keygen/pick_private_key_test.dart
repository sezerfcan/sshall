import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/keygen/pick_private_key.dart';

void main() {
  group('decodeKeyBytes', () {
    test('decodes plain ASCII PEM text unchanged', () {
      const pem =
          '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n';
      expect(decodeKeyBytes(utf8.encode(pem)), pem);
    });

    test('strips/keeps a UTF-8 BOM as lenient decode (no mangling)', () {
      // A file may carry a UTF-8 BOM. Lenient UTF-8 decode must not throw and
      // must not turn bytes into broken code units the way String.fromCharCodes
      // on raw bytes would.
      final withBom = [0xEF, 0xBB, 0xBF, ...utf8.encode('key')];
      final decoded = decodeKeyBytes(withBom);
      expect(decoded.endsWith('key'), true);
    });

    test('does not throw on malformed bytes (allowMalformed)', () {
      // 0xFF is not valid UTF-8; lenient decode replaces it instead of throwing.
      expect(() => decodeKeyBytes([0xFF, 0xFE, 0x00]), returnsNormally);
    });

    test('empty bytes decode to empty string', () {
      expect(decodeKeyBytes(const []), '');
    });
  });
}
