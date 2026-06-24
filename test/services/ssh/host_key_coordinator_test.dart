import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/services/ssh/host_key_coordinator.dart';

void main() {
  final c = HostKeyCoordinator();
  const pin = HostKeyPin(hostPort: 'h:22', keyType: 'ssh-ed25519', sha256: 'AAA');

  test('first use when no pin exists', () {
    expect(
      c.evaluate(hostPort: 'h:22', keyType: 'ssh-ed25519', sha256: 'AAA', pins: const []),
      HostKeyVerdict.firstUse,
    );
  });

  test('match when pin equals presented key', () {
    expect(
      c.evaluate(hostPort: 'h:22', keyType: 'ssh-ed25519', sha256: 'AAA', pins: [pin]),
      HostKeyVerdict.match,
    );
  });

  test('mismatch when pin differs', () {
    expect(
      c.evaluate(hostPort: 'h:22', keyType: 'ssh-ed25519', sha256: 'BBB', pins: [pin]),
      HostKeyVerdict.mismatch,
    );
  });

  test('different key type for same host is first use, not mismatch', () {
    expect(
      c.evaluate(hostPort: 'h:22', keyType: 'ssh-rsa', sha256: 'BBB', pins: [pin]),
      HostKeyVerdict.firstUse,
    );
  });
}
