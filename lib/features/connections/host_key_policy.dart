import '../../data/models/host_key_pin.dart';
import '../../services/ssh/host_key_coordinator.dart';

/// Decides the host-key action given current pins. Returns null when the UI
/// must prompt the user (first use or mismatch); otherwise the auto-decision.
class HostKeyPolicy {
  final HostKeyCoordinator coordinator;
  HostKeyPolicy(this.coordinator);

  /// (autoAccept, mismatch). autoAccept==null means "ask the user".
  ({bool? autoAccept, bool mismatch}) decide({
    required String hostPort,
    required String keyType,
    required String sha256,
    required List<HostKeyPin> pins,
  }) {
    final verdict = coordinator.evaluate(
        hostPort: hostPort, keyType: keyType, sha256: sha256, pins: pins);
    return switch (verdict) {
      HostKeyVerdict.match => (autoAccept: true, mismatch: false),
      HostKeyVerdict.firstUse => (autoAccept: null, mismatch: false),
      HostKeyVerdict.mismatch => (autoAccept: null, mismatch: true),
    };
  }
}
