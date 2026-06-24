import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sshall/features/sftp/local_fs_controller.dart';

void main() {
  late Directory tmp;
  final fs = LocalFsController();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sftp_local_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('list returns entries with dir/file flags', () async {
    await File(p.join(tmp.path, 'a.txt')).writeAsString('hi');
    await Directory(p.join(tmp.path, 'sub')).create();
    final entries = await fs.list(tmp.path);
    final byName = {for (final e in entries) e.name: e};
    expect(byName['a.txt']!.isDir, false);
    expect(byName['a.txt']!.size, 2);
    expect(byName['sub']!.isDir, true);
  });

  test('mkdir / rename / delete / exists', () async {
    final dir = p.join(tmp.path, 'new');
    await fs.mkdir(dir);
    expect(await fs.exists(dir), true);
    final renamed = p.join(tmp.path, 'renamed');
    await fs.rename(dir, renamed);
    expect(await fs.exists(dir), false);
    expect(await fs.exists(renamed), true);
    await fs.delete(renamed, isDir: true);
    expect(await fs.exists(renamed), false);
  });
}
