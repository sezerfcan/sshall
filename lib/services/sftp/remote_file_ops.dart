import '../../data/models/remote_entry.dart';
import 'sftp_messages.dart';

/// Backend-agnostic remote file operations consumed by the file pane, providers,
/// and transfer wiring. Implemented by SftpSession (real SFTP) and
/// DockerFileBackend (docker exec/cp, later task). See ADR 0028.
abstract class RemoteFileOps {
  Future<List<RemoteEntry>> list(String path);
  Future<RemoteEntry?> stat(String path);
  Future<void> mkdir(String path);
  Future<void> rename(String from, String to);
  Future<void> remove(String path, {required bool isDir});
  Future<void> chmod(String path, int mode);
  int startDownload(String remotePath, String localFinalPath);
  int startUpload(String localPath, String remoteFinalPath);
  void cancel(int transferId);
  Stream<SftpEvent> get transfers;
  Future<void> close();
}
