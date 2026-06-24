import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sshall/features/docker/docker_providers.dart';
import 'package:sshall/services/docker/docker_host.dart';
import 'package:sshall/services/docker/local_docker_host.dart';

void main() {
  test('localContainerListProvider surfaces daemonNotRunning as AsyncError', () async {
    final container = ProviderContainer(overrides: [
      localDockerHostProvider.overrideWithValue(
        LocalDockerHost(runner: (exe, args) async => ProcessResult(
            0, 1, '', 'Cannot connect to the Docker daemon. Is the docker daemon running?')),
      ),
    ]);
    addTearDown(container.dispose);
    await expectLater(
      container.read(localContainerListProvider.future),
      throwsA(isA<DockerException>()
          .having((e) => e.kind, 'kind', DockerErrorKind.daemonNotRunning)),
    );
  });

  test('localContainerListProvider returns the parsed list on success', () async {
    final container = ProviderContainer(overrides: [
      localDockerHostProvider.overrideWithValue(
        LocalDockerHost(runner: (exe, args) async => ProcessResult(0, 0,
            '{"ID":"a","Names":"api","Image":"nginx","State":"running","Status":"Up","Ports":""}\n', '')),
      ),
    ]);
    addTearDown(container.dispose);
    final list = await container.read(localContainerListProvider.future);
    expect(list.single.name, 'api');
  });
}
