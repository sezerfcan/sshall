import 'dart:io';
import 'dart:typed_data';

/// Raw persistence of the encrypted vault blob at [path].
class VaultFile {
  final String path;
  const VaultFile(this.path);

  Future<bool> exists() => File(path).exists();

  Future<Uint8List?> read() async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// Atomic write: write to a unique sibling temp file, flush it, then rename
  /// over the target. `rename` is atomic on the same filesystem, so a crash or
  /// power loss mid-write leaves the previous vault intact instead of a
  /// truncated, unrecoverable blob. The temp name is unique (pid + timestamp)
  /// so it can't collide with another writer, and is cleaned up if the rename
  /// fails so a failed write never orphans a `.tmp` file.
  Future<void> write(Uint8List blob) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await tmp.writeAsBytes(blob, flush: true);
      await tmp.rename(path);
    } catch (_) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {/* best-effort cleanup */}
      }
      rethrow;
    }
  }

  /// Remove the vault file if present. Idempotent: deleting a vault that was
  /// never created (or was already reset) is a no-op, not an error. Used by the
  /// "forgot passphrase" reset — there is nothing to securely overwrite because
  /// the blob is already encrypted and the key is gone (ADR 0011).
  Future<void> delete() async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
