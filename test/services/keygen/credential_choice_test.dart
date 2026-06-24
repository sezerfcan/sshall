import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/keygen/credential_choice.dart';

void main() {
  group('credentialFrom', () {
    test('password mode: secret is the password, no passphrase, not a key', () {
      final c = credentialFrom(
        useKey: false,
        password: 'hunter2',
        pem: 'PEM-IGNORED',
        keyPassphrase: 'kp-ignored',
      );
      expect(c.isKey, isFalse);
      expect(c.secret, 'hunter2');
      expect(c.passphrase, isNull);
    });

    test('key mode: secret is the pem, passphrase carried when non-empty', () {
      final c = credentialFrom(
        useKey: true,
        password: 'pw-ignored',
        pem: 'PEM-DATA',
        keyPassphrase: 's3cret',
      );
      expect(c.isKey, isTrue);
      expect(c.secret, 'PEM-DATA');
      expect(c.passphrase, 's3cret');
    });

    test('key mode: empty passphrase becomes null', () {
      final c = credentialFrom(
        useKey: true,
        password: '',
        pem: 'PEM-DATA',
        keyPassphrase: '',
      );
      expect(c.isKey, isTrue);
      expect(c.secret, 'PEM-DATA');
      expect(c.passphrase, isNull);
    });

    test('password mode: a key passphrase is never carried', () {
      final c = credentialFrom(
        useKey: false,
        password: 'pw',
        pem: 'PEM',
        keyPassphrase: 'nope',
      );
      expect(c.passphrase, isNull);
    });

    test('key mode with null pem yields a null secret (caller validates)', () {
      final c = credentialFrom(
        useKey: true,
        password: 'pw',
        pem: null,
        keyPassphrase: '',
      );
      expect(c.isKey, isTrue);
      expect(c.secret, isNull);
    });

    test('secretOrEmpty coalesces a null secret to empty string', () {
      final keyNoPem =
          credentialFrom(useKey: true, password: 'pw', pem: null, keyPassphrase: '');
      expect(keyNoPem.secretOrEmpty, '');
      final pw =
          credentialFrom(useKey: false, password: 'pw', pem: null, keyPassphrase: '');
      expect(pw.secretOrEmpty, 'pw');
    });
  });
}
