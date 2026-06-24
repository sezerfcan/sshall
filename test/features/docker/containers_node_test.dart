import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/docker/containers_node.dart';
import 'package:sshall/services/docker/docker_host.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

const _running = DockerContainer(
  id: 'a1',
  name: 'api',
  image: 'nginx:latest',
  state: 'running',
  status: 'Up 3 hours',
  ports: ['0.0.0.0:8080->80/tcp'],
);

const _exited = DockerContainer(
  id: 'w1',
  name: 'worker',
  image: 'busybox',
  state: 'exited',
  status: 'Exited (0) 5 minutes ago',
  ports: [],
);

Widget _pump(
  AsyncValue<List<DockerContainer>> containers, {
  VoidCallback? onRetry,
  void Function(DockerContainer)? onOpenTerminal,
  void Function(DockerContainer)? onBrowse,
}) =>
    MaterialApp(
      theme: appThemeData(AppThemeId.night),
      home: Scaffold(
        body: ContainersNode(
          containers: containers,
          onRetry: onRetry ?? () {},
          retryKeyId: 't',
          indent: 12,
          onOpenTerminal: onOpenTerminal ?? (_) {},
          onBrowse: onBrowse ?? (_) {},
        ),
      ),
    );

void main() {
  testWidgets('renders container rows and exited Terminal action is disabled',
      (tester) async {
    DockerContainer? terminalArg;
    DockerContainer? browseArg;

    await tester.pumpWidget(_pump(
      const AsyncValue.data([_running, _exited]),
      onOpenTerminal: (c) => terminalArg = c,
      onBrowse: (c) => browseArg = c,
    ));
    await tester.pumpAndSettle();

    // Both names render.
    expect(find.text('api'), findsOneWidget);
    expect(find.text('worker'), findsOneWidget);

    // Terminal action for the running container is enabled and fires.
    await tester.tap(find.byKey(const Key('container-terminal-a1')));
    await tester.pump();
    expect(terminalArg, _running);

    // Terminal action for the exited container is disabled (no callback).
    await tester.tap(find.byKey(const Key('container-terminal-w1')));
    await tester.pump();
    expect(terminalArg, _running, reason: 'disabled action must not fire');

    // Browse action for the running container fires with the right container.
    await tester.tap(find.byKey(const Key('container-browse-a1')));
    await tester.pump();
    expect(browseArg, _running);
  });

  testWidgets('empty data shows "Container yok"', (tester) async {
    await tester.pumpWidget(_pump(const AsyncValue.data([])));
    await tester.pumpAndSettle();
    expect(find.text('Container yok'), findsOneWidget);
  });

  testWidgets('loading state shows the spinner row', (tester) async {
    await tester.pumpWidget(
      _pump(const AsyncValue<List<DockerContainer>>.loading()),
    );
    await tester.pump();
    expect(find.text("Container'lar yükleniyor…"), findsOneWidget);
  });

  testWidgets(
      'daemonNotRunning error maps to its message and retry calls onRetry',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(_pump(
      AsyncValue<List<DockerContainer>>.error(
        DockerException(DockerErrorKind.daemonNotRunning, ''),
        StackTrace.empty,
      ),
      onRetry: () => retried++,
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Docker çalışmıyor — Docker Desktop\'ı başlatın'),
      findsOneWidget,
    );

    final retry = find.byKey(const Key('container-retry-t'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('notInstalled error maps to "Docker bulunamadı" with retry',
      (tester) async {
    await tester.pumpWidget(_pump(
      AsyncValue<List<DockerContainer>>.error(
        DockerException(
          DockerErrorKind.notInstalled,
          'docker: command not found',
        ),
        StackTrace.empty,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Docker bulunamadı'), findsOneWidget);
    expect(find.byKey(const Key('container-retry-t')), findsOneWidget);
  });

  testWidgets('denied error maps to "Docker erişim yetkisi yok"',
      (tester) async {
    await tester.pumpWidget(_pump(
      AsyncValue<List<DockerContainer>>.error(
        DockerException(DockerErrorKind.denied, 'permission denied'),
        StackTrace.empty,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Docker erişim yetkisi yok'), findsOneWidget);
  });

  testWidgets('unknown DockerException surfaces its message', (tester) async {
    await tester.pumpWidget(_pump(
      AsyncValue<List<DockerContainer>>.error(
        DockerException(DockerErrorKind.unknown, 'boom on host'),
        StackTrace.empty,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('boom on host'), findsOneWidget);
  });
}
