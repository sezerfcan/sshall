/// Pure helpers for Unix permission (mode) bits.
///
/// The low 9 bits of a Unix mode encode owner/group/other read/write/execute.
/// This knowledge used to live in two places: `octalMode`/`permString` on
/// [RemoteEntry] and the chmod dialog's hand-rolled `[8,7,6]/[5,4,3]/[2,1,0]`
/// bit indices with `1 << bit` / `^=`. Centralizing it here gives one tested
/// source of truth that both the model display and the dialog share.
class FileMode {
  FileMode._();

  /// Bit index of every rwx flag, grouped owner / group / other.
  /// Owner = bits 8,7,6 · group = 5,4,3 · other = 2,1,0.
  static const List<List<int>> bits = [
    [8, 7, 6],
    [5, 4, 3],
    [2, 1, 0],
  ];

  /// Low 9 permission bits of [mode]; `null` stays `null`-safe.
  static int? _perm(int? mode) => mode == null ? null : mode & 0x1FF;

  /// 3-digit octal of the low 9 permission bits; `'---'` when unknown.
  static String octal(int? mode) {
    final perm = _perm(mode);
    if (perm == null) return '---';
    return perm.toRadixString(8).padLeft(3, '0');
  }

  /// `rwxr-xr-x`-style string; all `'?'` when unknown.
  static String symbolic(int? mode) {
    final perm = _perm(mode);
    if (perm == null) return '?' * 9;
    const flags = ['r', 'w', 'x'];
    final sb = StringBuffer();
    for (var bit = 8; bit >= 0; bit--) {
      sb.write((perm & (1 << bit)) != 0 ? flags[2 - (bit % 3)] : '-');
    }
    return sb.toString();
  }

  /// Whether permission [bit] (0-8) is set in [mode].
  static bool has(int mode, int bit) => (mode & (1 << bit)) != 0;

  /// [mode] with permission [bit] (0-8) flipped.
  static int toggle(int mode, int bit) => mode ^ (1 << bit);
}
