import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/local_docker_file_backend.dart';
import 'package:sshall/services/sftp/sftp_messages.dart';

ProcessResult ok(String out) => ProcessResult(0, 0, out, '');

void main() {
  test('list runs docker exec ls -la and parses entries (no shell)', () async {
    final calls = <List<String>>[];
    final b = LocalDockerFileBackend('docker', 'api', runner: (exe, args) async {
      calls.add([exe, ...args]);
      return ok('-rw-r--r-- 1 r r 5 Jun 23 10:00 a.txt\n');
    });
    final entries = await b.list('/app');
    expect(entries.single.name, 'a.txt');
    expect(calls.single, ['docker', 'exec', 'api', 'ls', '-la', '/app']);
  });

  test('mkdir issues docker exec mkdir -p', () async {
    final calls = <List<String>>[];
    final b = LocalDockerFileBackend('docker', 'api', runner: (exe, args) async {
      calls.add(args);
      return ok('');
    });
    await b.mkdir('/app/new');
    expect(calls.single, ['exec', 'api', 'mkdir', '-p', '/app/new']);
  });

  test('remove dir uses rm -rf', () async {
    final calls = <List<String>>[];
    final b = LocalDockerFileBackend('docker', 'api', runner: (exe, args) async {
      calls.add(args);
      return ok('');
    });
    await b.remove('/app/x', isDir: true);
    expect(calls.single, ['exec', 'api', 'rm', '-rf', '/app/x']);
  });

  test('startDownload runs docker cp container:path local and emits Done',
      () async {
    final calls = <List<String>>[];
    final b = LocalDockerFileBackend('docker', 'api', runner: (exe, args) async {
      calls.add(args);
      return ok('');
    });
    final events = b.transfers.toList(); // collect after close
    final id = b.startDownload('/app/f.txt', '/tmp/f.txt');
    await Future<void>.delayed(Duration.zero);
    await b.close();
    final got = await events;
    expect(calls.single, ['cp', 'api:/app/f.txt', '/tmp/f.txt']);
    expect(id, 1);
    final last = got.last;
    expect(last, isA<TransferDone>());
    expect((last as TransferDone).transferId, id);
    expect(last.finalPath, '/tmp/f.txt');
  });
}
