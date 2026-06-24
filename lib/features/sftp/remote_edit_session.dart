/// Lifecycle of a single remote-edit session.
enum RemoteEditStatus { downloading, watching, uploading, conflict, error, closedRemote }

/// User's resolution when the remote changed under an active edit.
enum ConflictChoice { overwriteRemote, saveAsLocal, keepEditing }

/// One "open a remote file in an external editor and sync saves" session.
/// Pure data — no Flutter, no I/O. The controller owns the lifecycle.
class RemoteEditSession {
  final String id;
  final String remotePath;
  final String localTempPath;

  /// What we expect the remote to be at: captured at download, refreshed after
  /// each successful upload. Used for conflict detection.
  final int? baseMtimeMs;
  final int baseSize;

  /// Original remote permission bits (low 9), re-applied after upload.
  final int? mode;

  /// Last local temp stat we observed (to detect a new save).
  final int? lastLocalMtimeMs;
  final int lastLocalSize;

  final RemoteEditStatus status;
  final String? message;

  const RemoteEditSession({
    required this.id,
    required this.remotePath,
    required this.localTempPath,
    required this.baseMtimeMs,
    required this.baseSize,
    required this.mode,
    required this.lastLocalMtimeMs,
    required this.lastLocalSize,
    required this.status,
    required this.message,
  });

  /// Note: nullable params use `?? this.field`, so passing null preserves the
  /// existing value — fields cannot be cleared to null via copyWith (by design;
  /// the panel only renders `message` in error/conflict/closedRemote states).
  RemoteEditSession copyWith({
    int? baseMtimeMs,
    int? baseSize,
    int? mode,
    int? lastLocalMtimeMs,
    int? lastLocalSize,
    RemoteEditStatus? status,
    String? message,
  }) =>
      RemoteEditSession(
        id: id,
        remotePath: remotePath,
        localTempPath: localTempPath,
        baseMtimeMs: baseMtimeMs ?? this.baseMtimeMs,
        baseSize: baseSize ?? this.baseSize,
        mode: mode ?? this.mode,
        lastLocalMtimeMs: lastLocalMtimeMs ?? this.lastLocalMtimeMs,
        lastLocalSize: lastLocalSize ?? this.lastLocalSize,
        status: status ?? this.status,
        message: message ?? this.message,
      );
}
