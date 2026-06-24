import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/connect/widgets/connect_validation.dart';

void main() {
  group('validateHost', () {
    test('empty → error', () => expect(validateHost('  '), isNotNull));
    test('non-empty → ok', () => expect(validateHost('h'), isNull));
  });

  group('validateLabel', () {
    test('empty → error', () => expect(validateLabel(''), isNotNull));
    test('non-empty → ok', () => expect(validateLabel('Prod'), isNull));
  });

  group('validatePort', () {
    test('0 → error', () => expect(validatePort('0'), isNotNull));
    test('70000 → error', () => expect(validatePort('70000'), isNotNull));
    test('abc → error', () => expect(validatePort('abc'), isNotNull));
    test('empty → error', () => expect(validatePort(''), isNotNull));
    test('22 → ok', () => expect(validatePort('22'), isNull));
    test('65535 → ok', () => expect(validatePort('65535'), isNull));
  });

  group('validateCredential', () {
    test('password mode, empty password → error', () {
      expect(
        validateCredential(
          useKey: false,
          hasExistingIdentity: false,
          hasImportedKey: false,
          password: '',
        ),
        isNotNull,
      );
    });
    test('password mode, non-empty password → ok', () {
      expect(
        validateCredential(
          useKey: false,
          hasExistingIdentity: false,
          hasImportedKey: false,
          password: 'pw',
        ),
        isNull,
      );
    });
    test('key mode, nothing selected/imported → error', () {
      expect(
        validateCredential(
          useKey: true,
          hasExistingIdentity: false,
          hasImportedKey: false,
          password: '',
        ),
        isNotNull,
      );
    });
    test('key mode, existing identity → ok', () {
      expect(
        validateCredential(
          useKey: true,
          hasExistingIdentity: true,
          hasImportedKey: false,
          password: '',
        ),
        isNull,
      );
    });
    test('key mode, imported key → ok', () {
      expect(
        validateCredential(
          useKey: true,
          hasExistingIdentity: false,
          hasImportedKey: true,
          password: '',
        ),
        isNull,
      );
    });
  });

  group('ConnectFieldErrors', () {
    ConnectFieldErrors run({
      String label = 'L',
      String host = 'h',
      String port = '22',
      bool useKey = false,
      bool hasExistingIdentity = false,
      bool hasImportedKey = false,
      String password = 'pw',
    }) => ConnectFieldErrors.validate(
      label: label,
      host: host,
      port: port,
      useKey: useKey,
      hasExistingIdentity: hasExistingIdentity,
      hasImportedKey: hasImportedKey,
      password: password,
    );

    test('all valid → isValid, no firstInvalid', () {
      final e = run();
      expect(e.isValid, isTrue);
      expect(e.firstInvalid, isNull);
    });

    test('first-invalid precedence is label → host → port → credential', () {
      // Everything invalid: label wins.
      expect(
        run(label: '', host: '', port: '0', password: '').firstInvalid,
        ConnectField.label,
      );
      // Label ok, host empty: host wins.
      expect(
        run(host: '', port: '0', password: '').firstInvalid,
        ConnectField.host,
      );
      // Label+host ok, port bad: port wins.
      expect(run(port: '0', password: '').firstInvalid, ConnectField.port);
      // Only credential missing.
      expect(run(password: '').firstInvalid, ConnectField.credential);
    });

    test('errorFor maps each field', () {
      final e = run(label: '', host: '', port: 'x', password: '');
      expect(e.errorFor(ConnectField.label), isNotNull);
      expect(e.errorFor(ConnectField.host), isNotNull);
      expect(e.errorFor(ConnectField.port), isNotNull);
      expect(e.errorFor(ConnectField.credential), isNotNull);
    });
  });
}
