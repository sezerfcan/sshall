import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/docker_host.dart';
import 'package:sshall/services/docker/local_docker_host.dart';

void main() {
  test('listContainers parses docker ps output', () async {
    final host = LocalDockerHost(runner: (exe, args) async => ProcessResult(
        0,
        0,
        '{"ID":"a","Names":"api","Image":"nginx","State":"running","Status":"Up","Ports":""}\n',
        ''));
    final list = await host.listContainers();
    expect(list.single.name, 'api');
  });

  test('binary-not-found (ProcessException) -> notInstalled', () async {
    final host = LocalDockerHost(runner: (exe, args) async {
      throw ProcessException(exe, args, 'No such file or directory', 2);
    });
    expect(
      host.listContainers(),
      throwsA(isA<DockerException>()
          .having((e) => e.kind, 'kind', DockerErrorKind.notInstalled)),
    );
  });

  test('daemon down -> daemonNotRunning', () async {
    final host = LocalDockerHost(runner: (exe, args) async => ProcessResult(
        0, 1, '', 'Cannot connect to the Docker daemon. Is the docker daemon running?'));
    expect(
      host.listContainers(),
      throwsA(isA<DockerException>()
          .having((e) => e.kind, 'kind', DockerErrorKind.daemonNotRunning)),
    );
  });

  test('files() returns a RemoteFileOps backend', () {
    final host = LocalDockerHost(runner: (exe, args) async => ProcessResult(0, 0, '', ''));
    expect(host.files('api'), isNotNull);
  });
}
