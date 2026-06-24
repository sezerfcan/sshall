import '../../data/models/remote_entry.dart';
import '../sftp/remote_path.dart';

/// Parses `ls -la` output into [RemoteEntry] list. Tolerant of GNU coreutils
/// and busybox spacing. Skips the `total N` header, `.`/`..`, and any line that
/// does not match the expected shape (defensive — ADR 0015).
///
/// Expected line shape (whitespace-separated, name is the remainder):
///   <perm> <links> <owner> <group> <size> <mon> <day> <time-or-year> <name...>
List<RemoteEntry> parseLsLa(String parentPath, String output) {
  final entries = <RemoteEntry>[];
  for (final raw in output.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('total ')) continue;

    // perm field is 10 chars: type + 9 mode bits (may have trailing '.'/'+').
    final perm = line.split(RegExp(r'\s+')).first;
    if (perm.length < 10) continue;
    final typeChar = perm[0];
    if (!'-dlbcps'.contains(typeChar)) continue;

    final cols = line.split(RegExp(r'\s+'));
    // Need at least: perm links owner group size mon day time name => 9 cols.
    if (cols.length < 9) continue;

    final size = int.tryParse(cols[4]);
    if (size == null) continue;

    // Name = everything after the 8th column (perm..time). Rejoin to keep
    // spaces in filenames; locate by skipping the first 8 whitespace runs.
    final name = _nameAfter(line, 8);
    if (name.isEmpty || name == '.' || name == '..') continue;

    final isLink = typeChar == 'l';
    // Strip "name -> target" for symlinks.
    final displayName = isLink && name.contains(' -> ')
        ? name.substring(0, name.indexOf(' -> '))
        : name;

    entries.add(RemoteEntry(
      name: displayName,
      path: RemotePath.join(parentPath, displayName),
      isDir: typeChar == 'd',
      isSymlink: isLink,
      size: size,
      modified: null, // date parsing across locales is unreliable; omit in v1
      mode: _permBitsToMode(perm),
    ));
  }
  return entries;
}

/// Returns the substring after the [n]-th whitespace run (the filename column).
String _nameAfter(String line, int n) {
  var i = 0, fields = 0;
  while (i < line.length && fields < n) {
    while (i < line.length && line[i] != ' ' && line[i] != '\t') {
      i++;
    }
    while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    fields++;
  }
  return line.substring(i);
}

/// Converts the 9 rwx permission characters into low-9 mode bits.
int _permBitsToMode(String perm) {
  var mode = 0;
  const order = 'rwxrwxrwx';
  for (var i = 0; i < 9; i++) {
    final c = perm[i + 1];
    if (c != '-' && c == order[i]) mode |= 1 << (8 - i);
    // setuid/setgid/sticky (s/S/t/T) are not modeled in v1; treat as set bit.
    if (c == 's' || c == 't' || c == 'S' || c == 'T') mode |= 1 << (8 - i);
  }
  return mode;
}
