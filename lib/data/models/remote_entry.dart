/// A file-system entry shown in a [FilePane]. Implemented by both the remote
/// (SFTP) and local (`dart:io`) panes so the pane widget stays generic.
abstract class FsEntry {
  String get name;
  bool get isDir;
  bool get isSymlink;
  int get size;
  DateTime? get modified;

  /// Unix permission bits (low 9), or null when unknown.
  int? get mode;
}

class RemoteEntry implements FsEntry {
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

  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isSymlink,
    required this.size,
    required this.modified,
    required this.mode,
  });
}
