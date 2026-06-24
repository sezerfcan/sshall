/// Pure, isolate-free planner for recursive SFTP transfers (D2).
///
/// Walks a source tree (local or remote — direction-agnostic, dependencies
/// injected) and produces the destination directory skeleton plus a flat list
/// of file jobs, applying the overwrite policy. No Flutter, no dart:io, no
/// worker — unit-tested with in-memory fakes. See ADR 0016.
library;

/// A node in the source tree, normalized from a local `FileSystemEntity` or a
/// remote `RemoteEntry`.
class FsNode {
  final String name;
  final String path;
  final bool isDir;
  final bool isSymlink;
  final int size;
  const FsNode({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isSymlink,
    required this.size,
  });
}

/// One file to transfer: [srcPath] -> [destPath]. [destExists] is true when the
/// destination already had a file there (used by the askEach policy at the UI).
class FileJob {
  final String srcPath;
  final String destPath;
  final String name;
  final int size;
  final bool destExists;
  const FileJob({
    required this.srcPath,
    required this.destPath,
    required this.name,
    required this.size,
    required this.destExists,
  });
}

enum OverwritePolicy { overwrite, skipExisting, askEach }

class TransferPlan {
  final List<String> dirs; // dest dirs to create, parent-before-child
  final List<FileJob> files; // files to transfer (already filtered by policy)
  final int totalFiles;
  final int totalBytes;
  final int skippedExisting;
  final int skippedSymlink;
  final int skippedUnsafe;
  const TransferPlan({
    required this.dirs,
    required this.files,
    required this.totalFiles,
    required this.totalBytes,
    required this.skippedExisting,
    required this.skippedSymlink,
    required this.skippedUnsafe,
  });
}

class TransferPlanner {
  /// Builds a [TransferPlan] for transferring [root] INTO [destDir].
  ///
  /// - [listDir] lists a source directory's children (already [FsNode]s).
  /// - [destExists] reports whether a destination path already exists.
  /// - [joinDest] joins a destination parent + child name (POSIX `/` for
  ///   remote, platform separator for local).
  /// - [isSafeSegment] validates each child name against path traversal before
  ///   it is joined onto a destination path. The child names come from the
  ///   *source* tree (a remote `session.list` on download, the local FS on
  ///   upload), so a malicious/buggy server could return a name like `../evil`
  ///   or `a/b` that escapes the destination dir. Unsafe children are dropped
  ///   (not recursed into, not transferred) and counted in [TransferPlan.skippedUnsafe].
  Future<TransferPlan> plan({
    required FsNode root,
    required String destDir,
    required Future<List<FsNode>> Function(String path) listDir,
    required Future<bool> Function(String destPath) destExists,
    required String Function(String parent, String name) joinDest,
    required bool Function(String name) isSafeSegment,
    required OverwritePolicy policy,
  }) async {
    final dirs = <String>[];
    final files = <FileJob>[];
    var totalBytes = 0;
    var skippedExisting = 0;
    var skippedSymlink = 0;
    var skippedUnsafe = 0;

    Future<void> addFile(FsNode node, String destPath) async {
      final exists = await destExists(destPath);
      if (exists && policy == OverwritePolicy.skipExisting) {
        skippedExisting++;
        return;
      }
      files.add(FileJob(
        srcPath: node.path,
        destPath: destPath,
        name: node.name,
        size: node.size,
        destExists: exists,
      ));
      totalBytes += node.size;
    }

    Future<void> walk(FsNode dir, String destPath) async {
      dirs.add(destPath); // pre-order: parent before any descendant
      final children = await listDir(dir.path);
      for (final child in children) {
        // Guard first: a source-supplied name that isn't a single safe segment
        // (e.g. `../evil`, `a/b`) would escape the destination dir once joined.
        if (!isSafeSegment(child.name)) {
          skippedUnsafe++;
          continue;
        }
        if (child.isSymlink) {
          skippedSymlink++;
          continue;
        }
        if (child.isDir) {
          await walk(child, joinDest(destPath, child.name));
        } else {
          await addFile(child, joinDest(destPath, child.name));
        }
      }
    }

    if (root.isSymlink) {
      skippedSymlink++;
    } else if (root.isDir) {
      await walk(root, joinDest(destDir, root.name));
    } else {
      await addFile(root, joinDest(destDir, root.name));
    }

    return TransferPlan(
      dirs: dirs,
      files: files,
      totalFiles: files.length,
      totalBytes: totalBytes,
      skippedExisting: skippedExisting,
      skippedSymlink: skippedSymlink,
      skippedUnsafe: skippedUnsafe,
    );
  }
}
