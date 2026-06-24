import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/sftp/remote_file_ops.dart';

/// The active remote file session backing the SFTP view. Typed as the
/// backend-agnostic [RemoteFileOps] (ADR 0028) so the same view drives both a
/// real SFTP [SftpSession] (host connect flow) and a [DockerFileBackend]
/// (container browse via docker exec/cp). The view consumes only RemoteFileOps
/// members; the SFTP-only host-key/connect bits live in the connect flow.
final sftpSessionProvider = StateProvider<RemoteFileOps?>((ref) => null);
final sftpHostProvider = StateProvider<String?>((ref) => null);
