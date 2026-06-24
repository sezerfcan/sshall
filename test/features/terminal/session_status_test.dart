import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/session_status.dart';

void main() {
  group('classifyError — code → cause', () {
    test('auth code → auth cause, error state, raw preserved', () {
      final s = classifyError('auth', 'wrong password');
      expect(s.state, SessionState.error);
      expect(s.cause, ErrorCause.auth);
      expect(s.rawMessage, 'wrong password');
    });

    test('hostkey code → hostKeyMismatch cause', () {
      final s = classifyError('hostkey', 'Host key rejected');
      expect(s.state, SessionState.error);
      expect(s.cause, ErrorCause.hostKeyMismatch);
      expect(s.rawMessage, 'Host key rejected');
    });

    test('unknown code → unknown cause', () {
      final s = classifyError('weird', 'something odd');
      expect(s.cause, ErrorCause.unknown);
      expect(s.rawMessage, 'something odd');
    });
  });

  group('classifyError — network sub-classification', () {
    test('DNS phrasings → dns', () {
      for (final msg in const [
        'SocketException: Failed host lookup: "no.such.host"',
        'Could not resolve hostname no.such.host',
        'Name or service not known',
        'nodename nor servname provided',
      ]) {
        expect(
          classifyError('network', msg).cause,
          ErrorCause.dns,
          reason: msg,
        );
      }
    });

    test('refused phrasings → refused', () {
      for (final msg in const [
        'SocketException: Connection refused (OS Error: Connection refused, errno = 61)',
        'Connection refused',
      ]) {
        expect(
          classifyError('network', msg).cause,
          ErrorCause.refused,
          reason: msg,
        );
      }
    });

    test('timeout phrasings → timeout', () {
      for (final msg in const [
        'TimeoutException after 0:00:10.000000: Future not completed',
        'Connection timed out',
        'operation timeout',
      ]) {
        expect(
          classifyError('network', msg).cause,
          ErrorCause.timeout,
          reason: msg,
        );
      }
    });

    test('unrecognised network message → unknown (raw kept)', () {
      final s = classifyError('network', 'some unmapped network thing');
      expect(s.cause, ErrorCause.unknown);
      expect(s.rawMessage, 'some unmapped network thing');
    });
  });

  test('rawMessage preserved for every cause (Detaylar)', () {
    for (final code in const ['auth', 'hostkey', 'network', 'unknown']) {
      final s = classifyError(code, 'raw-$code');
      expect(s.rawMessage, 'raw-$code');
    }
  });

  group('causeCopy — Turkish title/hint/warning', () {
    test('auth copy', () {
      final c = causeCopy(ErrorCause.auth);
      expect(c.title, 'Kimlik doğrulama başarısız');
      expect(c.hint, 'Kullanıcı adı, şifre veya anahtarı kontrol edin');
      expect(c.warning, isFalse);
    });

    test('hostKeyMismatch is a warning with the DEĞİŞTİ title', () {
      final c = causeCopy(ErrorCause.hostKeyMismatch);
      expect(c.title, 'Ana makine anahtarı DEĞİŞTİ');
      expect(c.warning, isTrue);
      expect(c.hint, contains('MITM'));
    });

    test('dns/refused/timeout each carry a distinct title and remedy', () {
      final dns = causeCopy(ErrorCause.dns);
      final refused = causeCopy(ErrorCause.refused);
      final timeout = causeCopy(ErrorCause.timeout);
      expect(dns.title, 'Ana makine bulunamadı (DNS)');
      expect(refused.title, 'Bağlantı reddedildi');
      expect(timeout.title, 'Zaman aşımı');
      final hints = {dns.hint, refused.hint, timeout.hint};
      expect(hints.length, 3, reason: 'each remedy must be distinct');
    });

    test('unknown is generic', () {
      final c = causeCopy(ErrorCause.unknown);
      expect(c.title, 'Bağlantı hatası');
      expect(c.warning, isFalse);
    });
  });

  group('userInitiated separates close from drop (D1)', () {
    test('closedByUser vs dropped are distinguishable', () {
      const closed = SessionStatus.closedByUser();
      const dropped = SessionStatus.dropped();
      expect(closed.state, SessionState.disconnected);
      expect(dropped.state, SessionState.disconnected);
      expect(closed.userInitiated, isTrue);
      expect(dropped.userInitiated, isFalse);
      expect(closed.canReconnect, isFalse);
      expect(dropped.canReconnect, isTrue);
    });

    test('error always offers reconnect', () {
      expect(classifyError('auth', 'x').canReconnect, isTrue);
    });
  });

  group('statusLabel — localized (no raw English)', () {
    test('each state maps to Turkish', () {
      expect(statusLabel(const SessionStatus.connecting()), 'Bağlanılıyor…');
      expect(
        statusLabel(const SessionStatus.authenticating()),
        'Kimlik doğrulanıyor…',
      );
      expect(statusLabel(const SessionStatus.connected()), 'Bağlı');
      expect(statusLabel(classifyError('auth', 'x')), 'Hata');
      expect(statusLabel(const SessionStatus.dropped()), 'Bağlantı kesildi');
      expect(statusLabel(const SessionStatus.closedByUser()), 'Kapatıldı');
    });
  });
}
