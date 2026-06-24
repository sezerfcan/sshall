import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/connect/widgets/host_paste_parser.dart';

void main() {
  group('parseHostPaste', () {
    test('bare host', () {
      final r = parseHostPaste('example.com');
      expect(r.host, 'example.com');
      expect(r.username, isNull);
      expect(r.port, isNull);
      expect(r.isStructured, isFalse);
    });

    test('user@host', () {
      final r = parseHostPaste('root@example.com');
      expect(r.username, 'root');
      expect(r.host, 'example.com');
      expect(r.port, isNull);
      expect(r.isStructured, isTrue);
    });

    test('user@host:port', () {
      final r = parseHostPaste('root@example.com:2222');
      expect(r.username, 'root');
      expect(r.host, 'example.com');
      expect(r.port, 2222);
      expect(r.isStructured, isTrue);
    });

    test('host:port (no user)', () {
      final r = parseHostPaste('example.com:2222');
      expect(r.username, isNull);
      expect(r.host, 'example.com');
      expect(r.port, 2222);
      expect(r.isStructured, isTrue);
    });

    test('ssh user@host -p N', () {
      final r = parseHostPaste('ssh root@example.com -p 2222');
      expect(r.username, 'root');
      expect(r.host, 'example.com');
      expect(r.port, 2222);
    });

    test('ssh user@host -p N with extra options', () {
      final r = parseHostPaste('ssh deploy@10.0.0.5 -p 2200 -i ~/.ssh/id');
      expect(r.username, 'deploy');
      expect(r.host, '10.0.0.5');
      expect(r.port, 2200);
    });

    test('bracketed IPv6 without port', () {
      final r = parseHostPaste('[2001:db8::1]');
      expect(r.host, '2001:db8::1');
      expect(r.port, isNull);
      expect(r.username, isNull);
    });

    test('bracketed IPv6 with user and port', () {
      final r = parseHostPaste('root@[2001:db8::1]:2222');
      expect(r.username, 'root');
      expect(r.host, '2001:db8::1');
      expect(r.port, 2222);
    });

    test('unbracketed IPv6 literal is NOT split on its colons', () {
      final r = parseHostPaste('2001:db8::1');
      // Multiple colons → not a host:port; keep the whole literal as host.
      expect(r.host, '2001:db8::1');
      expect(r.port, isNull);
    });

    test('ssh with bracketed IPv6 and -p', () {
      final r = parseHostPaste('ssh root@[fe80::1] -p 22');
      expect(r.username, 'root');
      expect(r.host, 'fe80::1');
      expect(r.port, 22);
    });

    test('empty input', () {
      final r = parseHostPaste('   ');
      expect(r.host, isNull);
      expect(r.username, isNull);
      expect(r.port, isNull);
    });
  });
}
