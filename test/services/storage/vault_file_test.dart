import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/services/storage/keyring_store.dart';

void main() {
  test('VaultFile writes and reads back a blob', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_vault');
    final file = VaultFile('${dir.path}/vault.bin');
    expect(await file.exists(), isFalse);

    final blob = Uint8List.fromList([1, 2, 3, 250, 0, 9]);
    await file.write(blob);
    expect(await file.exists(), isTrue);
    expect(await file.read(), equals(blob));

    await dir.delete(recursive: true);
  });

  test('VaultFile.write is atomic and leaves no temp file behind', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_vault');
    final path = '${dir.path}/vault.bin';
    final file = VaultFile(path);

    await file.write(Uint8List.fromList([1, 1, 1]));
    // A second write replaces the contents and must not leave a .tmp sibling.
    await file.write(Uint8List.fromList([2, 2, 2, 2]));

    expect(await file.read(), equals([2, 2, 2, 2]));
    // No temp sibling left behind by either write.
    final leftovers = dir
        .listSync()
        .whereType<File>()
        .where((e) => e.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);

    await dir.delete(recursive: true);
  });

  test('InMemoryKeyring stores and clears the wrapped key', () async {
    final KeyringStore k = InMemoryKeyring();
    expect(await k.getWrappedKey(), isNull);
    await k.putWrappedKey('AAAA');
    expect(await k.getWrappedKey(), 'AAAA');
    await k.clear();
    expect(await k.getWrappedKey(), isNull);
  });

  test('delete removes an existing vault file', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_vf_del');
    final path = '${dir.path}/vault.bin';
    final vf = VaultFile(path);
    await vf.write(Uint8List.fromList([1, 2, 3]));
    expect(await vf.exists(), isTrue);

    await vf.delete();

    expect(await vf.exists(), isFalse);
    await dir.delete(recursive: true);
  });

  test('delete on a missing file is a no-op (idempotent)', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_vf_del2');
    final vf = VaultFile('${dir.path}/does-not-exist.bin');

    // Must not throw.
    await vf.delete();
    await vf.delete();

    expect(await vf.exists(), isFalse);
    await dir.delete(recursive: true);
  });
}
