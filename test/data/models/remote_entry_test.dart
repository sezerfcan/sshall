import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/remote_entry.dart';

void main() {
  test('RemoteEntry exposes FsEntry fields', () {
    final e = RemoteEntry(
      name: 'a.txt', path: '/home/a.txt', isDir: false, isSymlink: false,
      size: 12, modified: DateTime.utc(2026, 1, 2), mode: 0x1A4, // 0644
    );
    expect(e, isA<FsEntry>());
    expect(e.name, 'a.txt');
    expect(e.path, '/home/a.txt');
    expect(e.isDir, false);
    expect(e.size, 12);
  });
}
