import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/docker/docker_file_worker.dart';
import 'package:sshall/services/docker/shell_quote.dart';

void main() {
  group('shellSingleQuote', () {
    test('wraps plain string in single quotes', () {
      expect(shellSingleQuote('api'), "'api'");
    });

    test('preserves spaces inside the quotes (single arg)', () {
      expect(shellSingleQuote('/app/my file.txt'), "'/app/my file.txt'");
    });

    test("escapes embedded single quote as '\\''", () {
      expect(shellSingleQuote("/app/it's"), r"'/app/it'\''s'");
    });
  });

  group('dockerCpDownloadCommand', () {
    test('normal path quotes id + path, colon stays outside quotes', () {
      expect(
        dockerCpDownloadCommand('docker', 'api', '/app/f.txt'),
        "docker cp 'api':'/app/f.txt' -",
      );
    });

    test('path with a space keeps the space inside the quotes', () {
      // The single quoted argument preserves the space; `id:path` remains one
      // shell argument because the two quoted strings abut the colon.
      expect(
        dockerCpDownloadCommand('docker', 'api', '/app/my file.txt'),
        "docker cp 'api':'/app/my file.txt' -",
      );
    });

    test('path with a single quote is escaped', () {
      expect(
        dockerCpDownloadCommand('docker', 'api', "/app/it's"),
        r"docker cp 'api':'/app/it'\''s' -",
      );
    });

    test('container id is also quoted (defense-in-depth)', () {
      expect(
        dockerCpDownloadCommand('docker', "a'b", '/app/f.txt'),
        r"docker cp 'a'\''b':'/app/f.txt' -",
      );
    });
  });

  group('dockerCpUploadCommand', () {
    test('normal dest dir quotes id + path, colon stays outside quotes', () {
      expect(
        dockerCpUploadCommand('docker', 'api', '/app'),
        "docker cp - 'api':'/app'",
      );
    });

    test('dest dir with a space keeps the space inside the quotes', () {
      expect(
        dockerCpUploadCommand('docker', 'api', '/app/my dir'),
        "docker cp - 'api':'/app/my dir'",
      );
    });

    test('dest dir with a single quote is escaped', () {
      expect(
        dockerCpUploadCommand('docker', 'api', "/app/it's"),
        r"docker cp - 'api':'/app/it'\''s'",
      );
    });
  });
}
