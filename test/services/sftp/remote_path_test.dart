import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/remote_path.dart';

void main() {
  group('RemotePath.join', () {
    test('joins a child onto a normal absolute parent', () {
      expect(RemotePath.join('/home', 'x'), '/home/x');
      expect(RemotePath.join('/home/user', 'a.txt'), '/home/user/a.txt');
    });

    test('joins onto the "." relative root the way the old code did', () {
      // Preserve legacy behavior: both sftp_view ('$_remotePath/$name') and the
      // worker (parent + sep + name) produced "./x" when the parent was ".".
      expect(RemotePath.join('.', 'x'), './x');
    });

    test('does not double the separator when the parent ends with "/"', () {
      // Mirrors the worker's `parent.endsWith('/') ? '' : '/'` rule.
      expect(RemotePath.join('/', 'x'), '/x');
      expect(RemotePath.join('/a/', 'x'), '/a/x');
    });
  });

  group('RemotePath.isSafeSegment', () {
    test('accepts a plain single path segment', () {
      expect(RemotePath.isSafeSegment('file.txt'), true);
      expect(RemotePath.isSafeSegment('my-folder'), true);
      expect(RemotePath.isSafeSegment('a b c'), true);
      expect(RemotePath.isSafeSegment('.hidden'), true);
      expect(RemotePath.isSafeSegment('..dotfile'), true);
      expect(RemotePath.isSafeSegment('日本語'), true);
    });

    test('rejects empty / whitespace-only names', () {
      expect(RemotePath.isSafeSegment(''), false);
      expect(RemotePath.isSafeSegment('   '), false);
    });

    test('rejects "." and ".." (directory traversal anchors)', () {
      expect(RemotePath.isSafeSegment('.'), false);
      expect(RemotePath.isSafeSegment('..'), false);
    });

    test('rejects any POSIX path separator', () {
      expect(RemotePath.isSafeSegment('../etc/passwd'), false);
      expect(RemotePath.isSafeSegment('a/b'), false);
      expect(RemotePath.isSafeSegment('/abs'), false);
      expect(RemotePath.isSafeSegment('trailing/'), false);
    });

    test('rejects a Windows backslash separator', () {
      // The remote is POSIX, but a backslash could still escape a local join.
      expect(RemotePath.isSafeSegment('a\\b'), false);
      expect(RemotePath.isSafeSegment('..\\win'), false);
    });

    test('rejects control characters and the NUL byte', () {
      expect(RemotePath.isSafeSegment('a\x00b'), false);
      expect(RemotePath.isSafeSegment('a\nb'), false);
      expect(RemotePath.isSafeSegment('a\tb'), false);
      expect(RemotePath.isSafeSegment('a\x7fb'), false); // DEL
    });
  });

  group('RemotePath.parent', () {
    test('returns the POSIX parent directory', () {
      expect(RemotePath.parent('/home/user'), '/home');
      expect(RemotePath.parent('/home'), '/');
    });

    test('returns "." for the relative root and bare names', () {
      // Matches the previous p.dirname behavior the view relied on.
      expect(RemotePath.parent('.'), '.');
      expect(RemotePath.parent('foo'), '.');
      expect(RemotePath.parent('./foo'), '.');
    });

    test('keeps "/" as its own parent', () {
      expect(RemotePath.parent('/'), '/');
    });

    test('ignores a trailing slash', () {
      expect(RemotePath.parent('/a/b/'), '/a');
    });

    test('always uses POSIX "/" regardless of host platform', () {
      // The remote is always POSIX; a Windows `path` separator must never leak.
      expect(RemotePath.parent('/a/b').contains('\\'), false);
      expect(RemotePath.join('/a', 'b').contains('\\'), false);
    });
  });
}
