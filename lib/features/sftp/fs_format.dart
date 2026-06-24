/// Pure formatters for file-pane and transfer-queue cells (D3/D7). Kept
/// Flutter-free and unit-testable. UI strings are Turkish; the
/// numeric/byte/permission formats are locale-neutral.
library;

/// Human-readable byte size, e.g. `4.2 MB`. Mirrors the previous `_humanSize`
/// in the file pane so existing labels are unchanged.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

/// Bytes/sec as a rate, e.g. `4.2 MB/s`. Null/zero renders as `—`.
String humanRate(double? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec <= 0) return '—';
  return '${humanSize(bytesPerSec.round())}/s';
}

/// Compact ETA, e.g. `~12s`, `~3dk 5sn`. Null renders as `—`.
String humanEta(Duration? eta) {
  if (eta == null) return '—';
  final s = eta.inSeconds;
  if (s <= 0) return '0sn';
  if (s < 60) return '${s}sn';
  final m = s ~/ 60;
  final rem = s % 60;
  if (m < 60) return rem == 0 ? '${m}dk' : '${m}dk ${rem}sn';
  final h = m ~/ 60;
  final mm = m % 60;
  return mm == 0 ? '${h}sa' : '${h}sa ${mm}dk';
}

/// Short, locale-neutral modified date `YYYY-MM-DD HH:MM` (ISO-ish). Null
/// renders as `—`.
String humanDate(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Unix permission bits (low 9) as `rwxr-xr-x`. Null renders as `—`.
String humanMode(int? mode) {
  if (mode == null) return '—';
  const flags = 'rwxrwxrwx';
  final sb = StringBuffer();
  for (var i = 0; i < 9; i++) {
    final bit = 1 << (8 - i);
    sb.write((mode & bit) != 0 ? flags[i] : '-');
  }
  return sb.toString();
}
