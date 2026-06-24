import 'dart:io';
import 'package:path/path.dart' as p;
import '../../data/models/remote_entry.dart';

class LocalEntry implements FsEntry {
  @override
  final String name;
  final String path;
  @override
  final bool isDir;
  @override
  final bool isSymlink;
  @override
  final int size;
  @override
  final DateTime? modified;
  @override
  final int? mode;
  const LocalEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isSymlink,
    required this.size,
    required this.modified,
    required this.mode,
  });
}

class LocalFsController {
  Future<List<LocalEntry>> list(String path) async {
    final dir = Directory(path);
    final out = <LocalEntry>[];
    await for (final e in dir.list(followLinks: false)) {
      final st = await e.stat();
      out.add(LocalEntry(
        name: p.basename(e.path),
        path: e.path,
        isDir: st.type == FileSystemEntityType.directory,
        isSymlink: st.type == FileSystemEntityType.link,
        size: st.size,
        modified: st.modified,
        mode: st.mode & 0x1FF,
      ));
    }
    return out;
  }

  Future<void> mkdir(String path) => Directory(path).create();

  Future<void> rename(String from, String to) async {
    final type = await FileSystemEntity.type(from);
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  Future<void> delete(String path, {required bool isDir}) async {
    if (isDir) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  Future<bool> exists(String path) async =>
      (await FileSystemEntity.type(path)) != FileSystemEntityType.notFound;

  String join(String dir, String name) => p.join(dir, name);
}
