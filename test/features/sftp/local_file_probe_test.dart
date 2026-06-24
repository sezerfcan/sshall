import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sshall/features/sftp/local_file_probe.dart';

void main() {
  test('IoLocalFileProbe stats, ensures, lists and deletes', () async {
    final root = Directory.systemTemp.createTempSync('probe_test');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    const probe = IoLocalFileProbe();

    final sub = p.join(root.path, 'sess1');
    await probe.ensureDir(sub);
    expect(Directory(sub).existsSync(), isTrue);

    final f = p.join(sub, 'a.txt');
    File(f).writeAsStringSync('hello');
    final st = await probe.stat(f);
    expect(st, isNotNull);
    expect(st!.size, 5);

    expect(await probe.childDirs(root.path), contains(sub));

    await probe.deleteDir(sub);
    expect(Directory(sub).existsSync(), isFalse);

    expect(await probe.stat(p.join(sub, 'missing.txt')), isNull);
  });
}
