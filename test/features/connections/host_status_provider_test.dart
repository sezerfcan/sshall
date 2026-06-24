import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/connections/host_status_provider.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';
import 'package:sshall/services/ssh/ssh_service.dart';

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
  late ProviderContainer container;
  late TabsController tabs;

  setUp(() {
    container = ProviderContainer();
    tabs = container.read(tabsControllerProvider.notifier);
    // Prime the aggregate notifier so it attaches to live controllers.
    container.read(hostStatusProvider);
  });

  tearDown(() => container.dispose());

  test('no sessions → empty map (host reads idle)', () {
    expect(container.read(hostStatusProvider), isEmpty);
  });

  test('an open session is keyed by host:port with its live status', () async {
    final s = _FakeSession();
    tabs.openTerminal(s, 'web1', hostPort: 'web1:22');
    // Re-read after the tab change so the notifier re-attaches.
    container.read(hostStatusProvider);
    await Future<void>.delayed(Duration.zero);

    s.emit(StatusEvent(SshStatus.ready));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(hostStatusProvider)['web1:22']?.state,
      SessionState.connected,
    );
  });

  test('connecting → connected → disconnected transitions reflect', () async {
    final s = _FakeSession();
    tabs.openTerminal(s, 'web1', hostPort: 'web1:22');
    container.read(hostStatusProvider);
    await Future<void>.delayed(Duration.zero);

    // Starts connecting.
    expect(
      container.read(hostStatusProvider)['web1:22']?.state,
      SessionState.connecting,
    );

    s.emit(StatusEvent(SshStatus.ready));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(hostStatusProvider)['web1:22']?.state,
      SessionState.connected,
    );

    s.emit(ClosedEvent());
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(hostStatusProvider)['web1:22']?.state,
      SessionState.disconnected,
    );
  });

  test('endpoint-less sessions (no hostPort) are not keyed', () async {
    final s = _FakeSession();
    tabs.openTerminal(s, 'local-docker'); // no hostPort
    container.read(hostStatusProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(hostStatusProvider), isEmpty);
  });

  test('closing the tab drops the host from the map', () async {
    final s = _FakeSession();
    final id = tabs.openTerminal(s, 'web1', hostPort: 'web1:22');
    container.read(hostStatusProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(hostStatusProvider).containsKey('web1:22'), isTrue);

    tabs.close(id);
    container.read(hostStatusProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(hostStatusProvider).containsKey('web1:22'), isFalse);
  });

  test(
    'connected wins over a dropped duplicate session to the same host',
    () async {
      final live = _FakeSession();
      final dead = _FakeSession();
      tabs.openTerminal(live, 'web1', hostPort: 'web1:22');
      tabs.openTerminal(dead, 'web1-2', hostPort: 'web1:22');
      container.read(hostStatusProvider);
      await Future<void>.delayed(Duration.zero);

      live.emit(StatusEvent(SshStatus.ready));
      dead.emit(ClosedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(hostStatusProvider)['web1:22']?.state,
        SessionState.connected,
      );
    },
  );
}
