import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/docker_host.dart';
import 'package:sshall/services/docker/ssh_docker_host.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';

CommandResult ok(String out) => CommandResult(exitCode: 0, stdout: out, stderr: '');

void main() {
  const base = SshConnectParams(host: 'h', port: 22, username: 'u');

  test('dockerPsCommand builds json ps with --all', () {
    expect(dockerPsCommand('docker', all: true),
        "docker ps --all --no-trunc --format '{{json .}}'");
    expect(dockerPsCommand('sudo docker', all: false),
        "sudo docker ps --no-trunc --format '{{json .}}'");
  });

  test('dockerExecShellCommand falls back bash->sh', () {
    expect(dockerExecShellCommand('docker', 'api'),
        "docker exec -it api sh -c 'exec bash 2>/dev/null || exec sh'");
  });

  test('classifyDockerError maps stderr to kinds', () {
    expect(classifyDockerError(127, 'docker: command not found'),
        DockerErrorKind.notInstalled);
    expect(classifyDockerError(1, 'permission denied while trying to connect'),
        DockerErrorKind.denied);
    expect(classifyDockerError(1, 'something else'), DockerErrorKind.unknown);
  });

  test('listContainers parses runner output', () async {
    final host = SshDockerHost(base, runner: (cmd) async => ok(
        '{"ID":"a","Names":"api","Image":"nginx","State":"running","Status":"Up","Ports":""}\n'
        '{"ID":"b","Names":"db","Image":"pg","State":"exited","Status":"Exited","Ports":""}\n'));
    final list = await host.listContainers();
    expect(list.map((c) => c.name), ['api', 'db']);
  });

  test('listContainers throws DockerException(notInstalled)', () async {
    final host = SshDockerHost(base,
        runner: (cmd) async =>
            CommandResult(exitCode: 127, stdout: '', stderr: 'docker: command not found'));
    expect(host.listContainers(),
        throwsA(isA<DockerException>().having((e) => e.kind, 'kind', DockerErrorKind.notInstalled)));
  });
}
