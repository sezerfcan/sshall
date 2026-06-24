import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/transfer_plan.dart';

/// POSIX-style dest join, good enough for tests (mirrors RemotePath.join).
String _join(String parent, String name) =>
    parent.endsWith('/') ? '$parent$name' : '$parent/$name';

/// In-memory source tree: path -> children.
class _Tree {
  final Map<String, List<FsNode>> children;
  _Tree(this.children);
  Future<List<FsNode>> list(String path) async => children[path] ?? const [];
}

FsNode _dir(String name, String path) =>
    FsNode(name: name, path: path, isDir: true, isSymlink: false, size: 0);
FsNode _file(String name, String path, int size) =>
    FsNode(name: name, path: path, isDir: false, isSymlink: false, size: size);

/// Mirrors RemotePath.isSafeSegment for the planner's traversal guard.
bool _safe(String n) =>
    n.isNotEmpty &&
    n != '.' &&
    n != '..' &&
    !n.contains('/') &&
    !n.contains('\\');

void main() {
  test('single file: no dirs, one job, totals', () async {
    final plan = await TransferPlanner().plan(
      root: _file('a.txt', '/src/a.txt', 10),
      destDir: '/dst',
      listDir: (_) async => const [],
      destExists: (_) async => false,
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.overwrite,
    );
    expect(plan.dirs, isEmpty);
    expect(plan.files.single.srcPath, '/src/a.txt');
    expect(plan.files.single.destPath, '/dst/a.txt');
    expect(plan.totalFiles, 1);
    expect(plan.totalBytes, 10);
  });

  test('nested tree: dirs shallow->deep, flat files, totals', () async {
    final tree = _Tree({
      '/src/docs': [_file('r.txt', '/src/docs/r.txt', 1), _dir('sub', '/src/docs/sub')],
      '/src/docs/sub': [_file('s.txt', '/src/docs/sub/s.txt', 2)],
    });
    final plan = await TransferPlanner().plan(
      root: _dir('docs', '/src/docs'),
      destDir: '/dst',
      listDir: tree.list,
      destExists: (_) async => false,
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.overwrite,
    );
    // Parent before any descendant.
    expect(plan.dirs, ['/dst/docs', '/dst/docs/sub']);
    expect(plan.files.map((f) => f.destPath).toSet(),
        {'/dst/docs/r.txt', '/dst/docs/sub/s.txt'});
    expect(plan.totalFiles, 2);
    expect(plan.totalBytes, 3);
  });

  test('skipExisting drops existing dest files and counts them', () async {
    final tree = _Tree({
      '/src/d': [_file('keep.txt', '/src/d/keep.txt', 5), _file('skip.txt', '/src/d/skip.txt', 7)],
    });
    final plan = await TransferPlanner().plan(
      root: _dir('d', '/src/d'),
      destDir: '/dst',
      listDir: tree.list,
      destExists: (p) async => p == '/dst/d/skip.txt',
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.skipExisting,
    );
    expect(plan.files.map((f) => f.name), ['keep.txt']);
    expect(plan.skippedExisting, 1);
    expect(plan.totalBytes, 5);
  });

  test('overwrite keeps existing dest files but flags destExists', () async {
    final tree = _Tree({
      '/src/d': [_file('x.txt', '/src/d/x.txt', 3)],
    });
    final plan = await TransferPlanner().plan(
      root: _dir('d', '/src/d'),
      destDir: '/dst',
      listDir: tree.list,
      destExists: (_) async => true,
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.overwrite,
    );
    expect(plan.files.single.destExists, isTrue);
    expect(plan.skippedExisting, 0);
  });

  test('symlinks are skipped and counted', () async {
    final tree = _Tree({
      '/src/d': [
        _file('f.txt', '/src/d/f.txt', 1),
        const FsNode(name: 'link', path: '/src/d/link', isDir: false, isSymlink: true, size: 0),
        const FsNode(name: 'ldir', path: '/src/d/ldir', isDir: true, isSymlink: true, size: 0),
      ],
    });
    final plan = await TransferPlanner().plan(
      root: _dir('d', '/src/d'),
      destDir: '/dst',
      listDir: tree.list,
      destExists: (_) async => false,
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.overwrite,
    );
    expect(plan.files.map((f) => f.name), ['f.txt']);
    expect(plan.skippedSymlink, 2);
    expect(plan.dirs, ['/dst/d']); // ldir NOT recursed into
  });

  test('empty dir produces a dest dir with no files', () async {
    final tree = _Tree({'/src/empty': const <FsNode>[]});
    final plan = await TransferPlanner().plan(
      root: _dir('empty', '/src/empty'),
      destDir: '/dst',
      listDir: tree.list,
      destExists: (_) async => false,
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.overwrite,
    );
    expect(plan.dirs, ['/dst/empty']);
    expect(plan.files, isEmpty);
  });

  test('unsafe child names are dropped (traversal guard) and counted', () async {
    // A buggy/malicious source returns children that would escape the dest dir.
    final tree = _Tree({
      '/src/d': [
        _file('ok.txt', '/src/d/ok.txt', 4),
        _file('../evil', '/src/d/../evil', 9),
        _file('a/b', '/src/d/a/b', 9),
      ],
    });
    final plan = await TransferPlanner().plan(
      root: _dir('d', '/src/d'),
      destDir: '/dst',
      listDir: tree.list,
      destExists: (_) async => false,
      joinDest: _join,
      isSafeSegment: _safe,
      policy: OverwritePolicy.overwrite,
    );
    // Only the legit child survives; both unsafe ones are dropped.
    expect(plan.files.map((f) => f.name), ['ok.txt']);
    expect(plan.skippedUnsafe, 2);
    expect(plan.totalBytes, 4);
    // No dest path for an unsafe child leaked into dirs/files.
    expect(plan.dirs, ['/dst/d']);
  });
}
