import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/connect/connect_dialog.dart';
import 'package:sshall/services/ssh/ssh_messages.dart';

void main() {
  const params = SshConnectParams(host: 'h', port: 22, username: 'u');

  test('two distinct actions', () {
    expect(ConnectAction.values, [
      ConnectAction.save,
      ConnectAction.saveAndConnect,
    ]);
  });

  test('save action does not imply connect', () {
    const r = ConnectDialogResult(
      action: ConnectAction.save,
      params: params,
      label: 'L',
    );
    expect(r.connect, isFalse);
  });

  test('saveAndConnect implies connect', () {
    const r = ConnectDialogResult(
      action: ConnectAction.saveAndConnect,
      params: params,
      label: 'L',
    );
    expect(r.connect, isTrue);
  });

  test('existing-identity selection carries existingAuthRef (D8)', () {
    const r = ConnectDialogResult(
      action: ConnectAction.save,
      params: params,
      label: 'L',
      existingAuthRef: 'i1',
    );
    expect(r.existingAuthRef, 'i1');
  });

  test('new-secret selection leaves existingAuthRef null (D8)', () {
    const r = ConnectDialogResult(
      action: ConnectAction.save,
      params: SshConnectParams(
        host: 'h',
        port: 22,
        username: 'u',
        password: 'pw',
      ),
      label: 'L',
    );
    expect(r.existingAuthRef, isNull);
    expect(r.params.password, 'pw');
  });

  test('folderId/tags are carried unconditionally (no save boolean — D1)', () {
    const r = ConnectDialogResult(
      action: ConnectAction.save,
      params: params,
      label: 'L',
      folderId: 'work',
      tags: ['prod', 'db'],
    );
    expect(r.folderId, 'work');
    expect(r.tags, ['prod', 'db']);
  });

  test('advanced docker fields are carried', () {
    const r = ConnectDialogResult(
      action: ConnectAction.save,
      params: params,
      label: 'L',
      docker: true,
      dockerBinary: 'sudo docker',
    );
    expect(r.docker, isTrue);
    expect(r.dockerBinary, 'sudo docker');
  });
}
