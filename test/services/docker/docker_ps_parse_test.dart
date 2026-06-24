import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/docker_host.dart';

void main() {
  test('parses a running container line', () {
    const line =
        '{"ID":"abc123","Names":"api","Image":"nginx:latest","State":"running","Status":"Up 3 hours","Ports":"0.0.0.0:8080->80/tcp"}';
    final c = parseDockerPsLine(line)!;
    expect(c.id, 'abc123');
    expect(c.name, 'api');
    expect(c.image, 'nginx:latest');
    expect(c.state, 'running');
    expect(c.isRunning, isTrue);
    expect(c.ports, contains('0.0.0.0:8080->80/tcp'));
  });

  test('handles empty ports and exited state', () {
    const line =
        '{"ID":"d4","Names":"worker","Image":"myapp:ci","State":"exited","Status":"Exited (0) 2h ago","Ports":""}';
    final c = parseDockerPsLine(line)!;
    expect(c.isRunning, isFalse);
    expect(c.ports, isEmpty);
  });

  test('splits multiple comma-separated ports', () {
    const line =
        '{"ID":"d5","Names":"db","Image":"postgres:16","State":"running","Status":"Up","Ports":"0.0.0.0:5432->5432/tcp, :::5432->5432/tcp"}';
    final c = parseDockerPsLine(line)!;
    expect(c.ports.length, 2);
  });

  test('returns null on malformed json', () {
    expect(parseDockerPsLine('not json'), isNull);
    expect(parseDockerPsLine(''), isNull);
    expect(parseDockerPsLine('{"Image":"x"}'), isNull); // missing ID/Names
  });
}
