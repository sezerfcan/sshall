import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/status_colors.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  const c = AppColors.night;

  test('state → color mapping (D8)', () {
    expect(statusColor(SessionState.connected, null, c), c.green);
    expect(statusColor(SessionState.connecting, null, c), c.amber);
    expect(statusColor(SessionState.authenticating, null, c), c.amber);
    expect(statusColor(SessionState.error, ErrorCause.auth, c), c.red);
    expect(
      statusColor(SessionState.error, ErrorCause.hostKeyMismatch, c),
      c.red,
    );
    expect(statusColor(SessionState.disconnected, null, c), c.textDim);
  });

  test('connecting is NEVER textDim/gray', () {
    expect(statusColor(SessionState.connecting, null, c), isNot(c.textDim));
    expect(statusColor(SessionState.authenticating, null, c), isNot(c.textDim));
  });

  test('statusColorOf delegates from a SessionStatus', () {
    expect(statusColorOf(const SessionStatus.connected(), c), c.green);
    expect(statusColorOf(classifyError('auth', 'x'), c), c.red);
  });

  test('statusPulses only for connecting/authenticating', () {
    expect(statusPulses(SessionState.connecting), isTrue);
    expect(statusPulses(SessionState.authenticating), isTrue);
    expect(statusPulses(SessionState.connected), isFalse);
    expect(statusPulses(SessionState.error), isFalse);
    expect(statusPulses(SessionState.disconnected), isFalse);
  });
}
