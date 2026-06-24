import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/features/connections/host_key_policy.dart';
import 'package:sshall/services/ssh/host_key_coordinator.dart';

void main() {
  final policy = HostKeyPolicy(HostKeyCoordinator());
  const pin = HostKeyPin(hostPort: 'h:22', keyType: 't', sha256: 'AAA');

  test('auto-accepts a matching pin', () {
    final d = policy.decide(
        hostPort: 'h:22', keyType: 't', sha256: 'AAA', pins: [pin]);
    expect(d.autoAccept, isTrue);
    expect(d.mismatch, isFalse);
  });

  test('asks on first use', () {
    final d = policy.decide(
        hostPort: 'h:22', keyType: 't', sha256: 'AAA', pins: const []);
    expect(d.autoAccept, isNull);
    expect(d.mismatch, isFalse);
  });

  test('flags mismatch and asks', () {
    final d = policy.decide(
        hostPort: 'h:22', keyType: 't', sha256: 'ZZZ', pins: [pin]);
    expect(d.autoAccept, isNull);
    expect(d.mismatch, isTrue);
  });
}
