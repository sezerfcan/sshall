import '../../data/models/host_key_pin.dart';

enum HostKeyVerdict { firstUse, match, mismatch }

class HostKeyCoordinator {
  HostKeyVerdict evaluate({
    required String hostPort,
    required String keyType,
    required String sha256,
    required List<HostKeyPin> pins,
  }) {
    final existing =
        pins.where((p) => p.hostPort == hostPort && p.keyType == keyType);
    if (existing.isEmpty) return HostKeyVerdict.firstUse;
    return existing.any((p) => p.sha256 == sha256)
        ? HostKeyVerdict.match
        : HostKeyVerdict.mismatch;
  }

  HostKeyPin pinFor({
    required String hostPort,
    required String keyType,
    required String sha256,
  }) =>
      HostKeyPin(hostPort: hostPort, keyType: keyType, sha256: sha256);
}
