import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/docker_host.dart';

void main() {
  test('daemon-down stderr maps to daemonNotRunning', () {
    expect(
      classifyDockerError(1, 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?'),
      DockerErrorKind.daemonNotRunning,
    );
  });
  test('not-found still maps to notInstalled', () {
    expect(classifyDockerError(127, 'docker: command not found'),
        DockerErrorKind.notInstalled);
  });
  test('permission still maps to denied', () {
    expect(classifyDockerError(1, 'permission denied while trying to connect'),
        DockerErrorKind.denied);
  });
  test('other still maps to unknown', () {
    expect(classifyDockerError(1, 'some other error'), DockerErrorKind.unknown);
  });
}
