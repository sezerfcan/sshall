import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/docker_file_backend.dart';
import 'package:sshall/services/docker/ssh_docker_host.dart';
import 'package:sshall/services/sftp/sftp_service.dart' show SftpException;
import 'package:sshall/services/ssh/ssh_messages.dart';

void main() {
  const base = SshConnectParams(host: 'h', port: 22, username: 'u');

  test('list runs docker exec ls and parses entries', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(
        exitCode: 0,
        stdout: '-rw-r--r-- 1 r r 5 Jun 23 10:00 a.txt\n',
        stderr: '',
      );
    });
    final entries = await backend.list('/app');
    expect(entries.single.name, 'a.txt');
    expect(commands.single, contains('docker exec api ls -la'));
    expect(commands.single, contains('/app'));
    await backend.close();
  });

  test('stat runs ls -lad and returns the entry', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(
        exitCode: 0,
        stdout: 'drwxr-xr-x 2 r r 4096 Jun 23 10:00 /app\n',
        stderr: '',
      );
    });
    final entry = await backend.stat('/app');
    expect(entry, isNotNull);
    expect(entry!.isDir, isTrue);
    expect(commands.single, contains('docker exec api ls -lad'));
    expect(commands.single, contains('/app'));
    await backend.close();
  });

  test('stat returns null on non-zero exit', () async {
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      return CommandResult(
          exitCode: 1, stdout: '', stderr: 'No such file or directory');
    });
    expect(await backend.stat('/nope'), isNull);
    await backend.close();
  });

  test('mkdir issues docker exec mkdir -p', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(exitCode: 0, stdout: '', stderr: '');
    });
    await backend.mkdir('/app/new');
    expect(commands.single, contains('mkdir -p'));
    expect(commands.single, contains('/app/new'));
    await backend.close();
  });

  test('rename issues mv with both quoted paths', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(exitCode: 0, stdout: '', stderr: '');
    });
    await backend.rename('/app/a', '/app/b');
    expect(commands.single, contains('mv'));
    expect(commands.single, contains('/app/a'));
    expect(commands.single, contains('/app/b'));
    await backend.close();
  });

  test('remove dir uses rm -rf', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(exitCode: 0, stdout: '', stderr: '');
    });
    await backend.remove('/app/x', isDir: true);
    expect(commands.single, contains('rm -rf'));
    await backend.close();
  });

  test('remove file uses rm -f', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(exitCode: 0, stdout: '', stderr: '');
    });
    await backend.remove('/app/x', isDir: false);
    expect(commands.single, contains('rm -f'));
    expect(commands.single, isNot(contains('rm -rf')));
    await backend.close();
  });

  test('chmod issues octal mode', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(exitCode: 0, stdout: '', stderr: '');
    });
    await backend.chmod('/app/x', 0x1ed); // 0755
    expect(commands.single, contains('chmod 755'));
    await backend.close();
  });

  test('failing metadata op throws SftpException with stderr message', () async {
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      return CommandResult(
          exitCode: 1, stdout: '', stderr: 'permission denied');
    });
    expect(
      backend.mkdir('/app/new'),
      throwsA(isA<SftpException>()
          .having((e) => e.message, 'message', 'permission denied')),
    );
    await backend.close();
  });

  test('paths with single quotes are escaped safely', () async {
    final commands = <String>[];
    final backend = DockerFileBackend(base, 'api', commandRunner: (cmd) async {
      commands.add(cmd);
      return CommandResult(exitCode: 0, stdout: '', stderr: '');
    });
    await backend.mkdir("/app/it's");
    // The single quote in the path is escaped via '\'' so the shell command
    // remains well-formed. Assert the exact full command (path quoted by _q,
    // then the whole inner command re-quoted by `sh -c`), so a regression in
    // either escaping layer or its placement is caught — not just the presence
    // of the escape sequence somewhere.
    expect(
      commands.single,
      r"""docker exec api sh -c 'mkdir -p '\''/app/it'\''\'\'''\''s'\'''""",
    );
    await backend.close();
  });

  test('tar round-trip preserves single-file bytes', () {
    final data = Uint8List.fromList(List.generate(300, (i) => i % 256));
    final ar = Archive()..addFile(ArchiveFile('a.bin', data.length, data));
    final tar = TarEncoder().encode(ar);
    final decoded = TarDecoder().decodeBytes(tar);
    final f = decoded.files.firstWhere((f) => f.isFile);
    expect(f.content, data);
  });
}
