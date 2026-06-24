// test/services/docker/ls_parse_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/ls_parse.dart';

void main() {
  test('parses GNU coreutils ls -la output', () {
    const out = '''
total 12
drwxr-xr-x 2 root root 4096 Jun 23 10:00 .
drwxr-xr-x 1 root root 4096 Jun 23 09:00 ..
-rw-r--r-- 1 root root  220 Jun 23 10:00 hello.txt
drwxr-xr-x 2 root root 4096 Jun 23 10:00 sub
lrwxrwxrwx 1 root root    7 Jun 23 10:00 link -> hello.txt
''';
    final entries = parseLsLa('/app', out);
    final names = entries.map((e) => e.name).toList();
    expect(names, containsAll(['hello.txt', 'sub', 'link']));
    expect(names, isNot(contains('.')));
    expect(names, isNot(contains('..')));

    final file = entries.firstWhere((e) => e.name == 'hello.txt');
    expect(file.isDir, isFalse);
    expect(file.path, '/app/hello.txt');
    expect(file.size, 220);
    expect(file.mode! & 0x1FF, 0x1A4); // rw-r--r-- = 0644

    expect(entries.firstWhere((e) => e.name == 'sub').isDir, isTrue);

    final link = entries.firstWhere((e) => e.name == 'link');
    expect(link.isSymlink, isTrue);
    expect(link.name, 'link'); // arrow target stripped
  });

  test('handles busybox ls -la (no total or different spacing)', () {
    const out =
        '-rw-r--r--    1 1000     1000           5 Jun 23 10:00 a.txt';
    final entries = parseLsLa('/', out);
    expect(entries.single.name, 'a.txt');
    expect(entries.single.size, 5);
  });

  test('skips malformed lines without throwing', () {
    const out = 'total 4\ngarbage line\n-rw-r--r-- 1 r r 1 Jun 23 10:00 ok';
    final entries = parseLsLa('/', out);
    expect(entries.single.name, 'ok');
  });
}
