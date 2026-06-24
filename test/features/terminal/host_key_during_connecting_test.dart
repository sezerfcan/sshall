import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/features/connections/host_key_policy.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/terminal_session_controller.dart';
import 'package:sshall/services/ssh/host_key_coordinator.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';

/// Regression guard (ADR 0006/0018 + ADR 0032 D2): the rich SessionStatus
/// refactor must NOT break the host-key flow. The tab now opens at `connecting`
/// and the controller translates worker events, but it must still leave the
/// HostKeyRequestEvent for the connect orchestrator to drive the dialog — and
/// the policy must still GATE trust (ask on first-use/mismatch, auto-accept on
/// match) while the session is connecting.
class _FakeSession implements SshSession {
  final _c = StreamController<WorkerEvent>.broadcast();
  void emit(WorkerEvent e) => _c.add(e);
  @override
  Stream<WorkerEvent> get events => _c.stream;
  @override
  WorkerEvent? get currentLifecycle => null;
  @override
  void sendInput(Uint8List data) {}
  @override
  void resize(int w, int h, int pw, int ph) {}
  @override
  void decideHostKey(bool accept) {}
  @override
  Uint8List takeOutputBacklog() => Uint8List(0);
  @override
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}

void main() {
  test('controller does NOT swallow HostKeyRequestEvent — a parallel listener '
      '(the connect orchestrator) still receives it while connecting', () async {
    final s = _FakeSession();
    final received = <HostKeyRequestEvent>[];
    // The orchestrator listens to the SAME broadcast stream the controller does.
    final orchestratorSub = s.events
        .where((e) => e is HostKeyRequestEvent)
        .listen((e) => received.add(e as HostKeyRequestEvent));
    final c = TerminalSessionController(s, hostPort: 'web1:22');

    // Still connecting (tab opened immediately, D2).
    expect(c.status.value.state, SessionState.connecting);

    s.emit(HostKeyRequestEvent('ssh-ed25519', 'SHA256:abc'));
    await Future<void>.delayed(Duration.zero);

    // The host-key request reached the orchestrator (the dialog driver); the
    // controller left it untouched (its status stays connecting).
    expect(received, hasLength(1));
    expect(c.status.value.state, SessionState.connecting);

    await orchestratorSub.cancel();
    await c.dispose();
  });

  group('policy gates trust during connect (unchanged by the refactor)', () {
    final policy = HostKeyPolicy(HostKeyCoordinator());
    const hostPort = 'web1:22';
    const keyType = 'ssh-ed25519';

    test('FIRST USE → must ask (gate, no auto-accept)', () {
      final d = policy.decide(
        hostPort: hostPort,
        keyType: keyType,
        sha256: 'SHA256:new',
        pins: const [],
      );
      expect(d.autoAccept, isNull, reason: 'first use must prompt');
      expect(d.mismatch, isFalse);
    });

    test('MISMATCH → must ask + flag mismatch (MITM gate)', () {
      final d = policy.decide(
        hostPort: hostPort,
        keyType: keyType,
        sha256: 'SHA256:changed',
        pins: const [
          HostKeyPin(
            hostPort: hostPort,
            keyType: keyType,
            sha256: 'SHA256:original',
          ),
        ],
      );
      expect(d.autoAccept, isNull, reason: 'mismatch must prompt');
      expect(d.mismatch, isTrue);
    });

    test('MATCH → auto-accept (known host connects without a prompt)', () {
      final d = policy.decide(
        hostPort: hostPort,
        keyType: keyType,
        sha256: 'SHA256:original',
        pins: const [
          HostKeyPin(
            hostPort: hostPort,
            keyType: keyType,
            sha256: 'SHA256:original',
          ),
        ],
      );
      expect(d.autoAccept, isTrue);
      expect(d.mismatch, isFalse);
    });
  });
}
