/// Pure helpers for manipulating *remote* (SFTP) paths.
///
/// The remote side is always POSIX, so these always use `/` as the separator —
/// independent of the host platform the app runs on. Previously the SFTP view
/// and worker built remote paths three different ways (manual `'$path/$name'`
/// string concat in the view, `p.dirname` for "up", and a hand-rolled
/// `endsWith('/') ? '' : '/'` separator in the worker). That risked a Windows
/// `path` separator leaking into a remote path and made the logic untestable.
/// Centralizing it here keeps a single, tested source of truth.
class RemotePath {
  RemotePath._();

  /// Joins [name] onto directory [parent], inserting a single `/` separator.
  ///
  /// Behavior is intentionally identical to the old call sites:
  /// - `join('/home', 'x')`  -> `/home/x`
  /// - `join('/', 'x')`      -> `/x`     (no doubled separator)
  /// - `join('/a/', 'x')`    -> `/a/x`   (parent's trailing slash absorbed)
  /// - `join('.', 'x')`      -> `./x`    (relative root, as before)
  static String join(String parent, String name) {
    final sep = parent.endsWith('/') ? '' : '/';
    return '$parent$sep$name';
  }

  /// Whether [name] is a safe *single* path segment to join onto a directory.
  ///
  /// This is the guard against path traversal: every user- or server-supplied
  /// name (mkdir, rename target, upload/download "keep both" name) is joined
  /// onto the current directory via [join] / `p.join`. Without validation a
  /// name like `../../etc/passwd`, `/abs/path`, or `a/b` escapes the current
  /// pane entirely. A safe segment must therefore be a single, literal file or
  /// directory name:
  ///
  /// - not empty and not whitespace-only;
  /// - not `.` or `..` (the traversal anchors themselves);
  /// - contains no path separator (`/` or `\`) — `\` is rejected too because the
  ///   local pane joins with the host separator, which is `\` on Windows;
  /// - contains no control characters (including NUL `\x00` and DEL `\x7f`),
  ///   which can truncate paths or smuggle escapes past naive consumers.
  ///
  /// Internal spaces are allowed (`"my file.txt"` is a perfectly valid name).
  static bool isSafeSegment(String name) {
    if (name.trim().isEmpty) return false;
    if (name == '.' || name == '..') return false;
    if (name.contains('/') || name.contains('\\')) return false;
    for (final unit in name.codeUnits) {
      // Reject C0 controls (0x00-0x1f) and DEL (0x7f).
      if (unit < 0x20 || unit == 0x7f) return false;
    }
    return true;
  }

  /// Returns the parent directory of [path], POSIX-style.
  ///
  /// Mirrors the `p.dirname` results the view relied on, but pinned to POSIX so
  /// the result never contains a backslash on Windows:
  /// - `parent('/home/user')` -> `/home`
  /// - `parent('/home')`      -> `/`
  /// - `parent('/')`          -> `/`
  /// - `parent('.')`          -> `.`
  /// - `parent('foo')`        -> `.`
  static String parent(String path) {
    if (path.isEmpty) return '.';
    // Drop a single trailing slash (but never reduce "/" to empty).
    var p = path;
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    final lastSlash = p.lastIndexOf('/');
    if (lastSlash < 0) return '.'; // bare name or "./foo" leftover -> "."
    if (lastSlash == 0) return '/'; // direct child of root
    return p.substring(0, lastSlash);
  }
}
