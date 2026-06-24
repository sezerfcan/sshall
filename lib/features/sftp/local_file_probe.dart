import 'dart:io';

/// Local-filesystem access used by the remote-edit controller: stat temp files
/// (to detect saves), ensure/delete session temp dirs, and list stale dirs for
/// startup cleanup. Seam so the controller is unit-testable with a fake.
abstract interface class LocalFileProbe {
  /// Modified-time (ms since epoch) and size, or null if the file is missing.
  Future<({int mtimeMs, int size})?> stat(String path);
  Future<void> ensureDir(String dirPath);
  Future<void> deleteDir(String dirPath);

  /// Immediate child directory paths of [rootPath] (empty if root missing).
  Future<List<String>> childDirs(String rootPath);
}

class IoLocalFileProbe implements LocalFileProbe {
  const IoLocalFileProbe();

  @override
  Future<({int mtimeMs, int size})?> stat(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    final s = await f.stat();
    return (mtimeMs: s.modified.millisecondsSinceEpoch, size: s.size);
  }

  @override
  Future<void> ensureDir(String dirPath) =>
      Directory(dirPath).create(recursive: true);

  @override
  Future<void> deleteDir(String dirPath) async {
    final d = Directory(dirPath);
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<List<String>> childDirs(String rootPath) async {
    final d = Directory(rootPath);
    if (!await d.exists()) return const [];
    return d
        .listSync()
        .whereType<Directory>()
        .map((e) => e.path)
        .toList();
  }
}
