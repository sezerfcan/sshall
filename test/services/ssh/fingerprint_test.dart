import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/ssh/fingerprint.dart';

void main() {
  // dartssh2's onVerifyHostKey passes the fingerprint as UTF-8 bytes of the
  // OpenSSH-style string "SHA256:<base64>" (see SSHHostkeyVerifyHandler doc and
  // _hostkeyFingerprint in dartssh2). formatSha256 must return just the base64
  // digest part; the dialog/storage add the "SHA256:" label.
  test('formatSha256 returns the base64 digest from dartssh2 fingerprint bytes',
      () {
    const digest = 'NBPiKskDrzz5AdGIRY7V31fdTIHcKZ23HDNT1JfZmDk';
    final fp = Uint8List.fromList(utf8.encode('SHA256:$digest'));
    expect(formatSha256(fp), digest);
  });

  test('formatSha256 does not double-prefix or double-encode', () {
    const digest = 'AAAABBBBCCCC';
    final fp = Uint8List.fromList(utf8.encode('SHA256:$digest'));
    final s = formatSha256(fp);
    expect(s.startsWith('SHA256:'), isFalse);
    expect(s.contains('='), isFalse);
    expect(s, digest);
  });
}
