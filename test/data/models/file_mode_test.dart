import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/file_mode.dart';

void main() {
  group('FileMode.octal', () {
    test('formats low 9 permission bits', () {
      expect(FileMode.octal(0x1FF), '777'); // rwxrwxrwx
      expect(FileMode.octal(0x1A4), '644'); // rw-r--r--
      expect(FileMode.octal(null), '---');
    });

    test('ignores high bits above the low 9', () {
      // 0o100644 (regular file, 0644) must still render as 644.
      expect(FileMode.octal(0x81A4), '644');
    });
  });

  group('FileMode.symbolic', () {
    test('renders rwx triples', () {
      expect(FileMode.symbolic(0x1FF), 'rwxrwxrwx');
      expect(FileMode.symbolic(0x1A4), 'rw-r--r--');
      expect(FileMode.symbolic(null), '?????????');
    });
  });

  group('bit indices', () {
    test('exposes the standard owner/group/other rwx bit layout', () {
      // Owner r/w/x = bits 8/7/6, group = 5/4/3, other = 2/1/0.
      expect(FileMode.bits, [
        [8, 7, 6],
        [5, 4, 3],
        [2, 1, 0],
      ]);
    });
  });

  group('has', () {
    test('reports whether a permission bit is set', () {
      const mode = 0x1A4; // 0644 -> owner rw, group r, other r
      expect(FileMode.has(mode, 8), true); // owner read
      expect(FileMode.has(mode, 7), true); // owner write
      expect(FileMode.has(mode, 6), false); // owner execute
      expect(FileMode.has(mode, 0), false); // other execute
    });
  });

  group('toggle', () {
    test('flips a single bit, preserving the rest', () {
      // The chmod dialog's exact scenario: 0644 + owner-execute -> 0744.
      expect(FileMode.toggle(0x1A4, 6), 0x1E4); // 0744
      // Toggling the same bit again returns to the original.
      expect(FileMode.toggle(0x1E4, 6), 0x1A4);
    });
  });
}
