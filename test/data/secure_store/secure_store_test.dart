import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/folders/folder_ops.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';

Future<SecureStore> _store(Directory dir, KeyringStore k) async => SecureStore(
      crypto: CryptoService(),
      file: VaultFile('${dir.path}/vault.bin'),
      keyring: k,
    );

void main() {
  test('create, persist, reopen and unlock recovers data', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final keyring = InMemoryKeyring();
    final s = await _store(dir, keyring);

    expect(await s.vaultExists(), isFalse);
    expect((await s.create('hunter2')).isOk, isTrue);
    expect(s.isUnlocked, isTrue);

    await s.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
              id: 'c1',
              label: 'box',
              host: 'h',
              folderId: null,
              username: 'u',
              port: 22,
              authRef: 'i1',
              tags: [],
              order: 0,
            ),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        ));

    // Reopen with a fresh instance, unlock with passphrase.
    final s2 = await _store(dir, InMemoryKeyring());
    expect(await s2.vaultExists(), isTrue);
    expect(s2.isUnlocked, isFalse);
    expect((await s2.unlock('hunter2')).isOk, isTrue);
    expect(s2.snapshot().valueOrNull!.connections.single.host, 'h');

    await dir.delete(recursive: true);
  });

  test('create refuses to overwrite an existing vault', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final s = await _store(dir, InMemoryKeyring());
    expect((await s.create('first')).isOk, isTrue);
    await s.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
              id: 'c1',
              label: 'box',
              host: 'h',
              folderId: null,
              username: 'u',
              port: 22,
              authRef: 'i1',
              tags: [],
              order: 0,
            ),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        ));

    // A second create must fail and must NOT wipe the existing vault.
    final r2 = await s.create('second');
    expect(r2.isOk, isFalse);
    expect(r2.failureOrNull, isA<StorageFailure>());

    // Original data is still intact and unlockable with the ORIGINAL passphrase.
    final s2 = await _store(dir, InMemoryKeyring());
    expect((await s2.unlock('first')).isOk, isTrue);
    expect(s2.snapshot().valueOrNull!.connections.single.host, 'h');
    // The second passphrase was never written.
    expect((await (await _store(dir, InMemoryKeyring())).unlock('second')).isOk,
        isFalse);

    await dir.delete(recursive: true);
  });

  test('unlock returns a failure (never throws) on an unsupported version byte',
      () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final path = '${dir.path}/vault.bin';
    final s = SecureStore(
        crypto: CryptoService(),
        file: VaultFile(path),
        keyring: InMemoryKeyring());
    expect((await s.create('pw')).isOk, isTrue);

    // Flip the version byte (index 5, right after the 5-byte "SSHAL" magic).
    final f = File(path);
    final bytes = await f.readAsBytes();
    bytes[5] = 0x99;
    await f.writeAsBytes(bytes, flush: true);

    final s2 = SecureStore(
        crypto: CryptoService(),
        file: VaultFile(path),
        keyring: InMemoryKeyring());
    final r = await s2.unlock('pw');
    expect(r.isOk, isFalse);
    expect(r.failureOrNull, isA<StorageFailure>());
    expect(s2.isUnlocked, isFalse);

    await dir.delete(recursive: true);
  });

  test('concurrent mutate calls do not lose writes (serialized)', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final s = await _store(dir, InMemoryKeyring());
    expect((await s.create('pw')).isOk, isTrue);

    // Fire two mutations WITHOUT awaiting the first. Without serialization both
    // would read the same empty base and the last write would clobber the first.
    final f1 = s.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
                id: 'a',
                label: 'a',
                host: 'a',
                folderId: null,
                username: 'u',
                port: 22,
                authRef: 'i',
                tags: [],
                order: 0),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        ));
    final f2 = s.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
                id: 'b',
                label: 'b',
                host: 'b',
                folderId: null,
                username: 'u',
                port: 22,
                authRef: 'i',
                tags: [],
                order: 0),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        ));
    await Future.wait([f1, f2]);

    final ids =
        s.snapshot().valueOrNull!.connections.map((c) => c.id).toList();
    expect(ids, containsAll(<String>['a', 'b']));

    // And both survive a reopen (persisted, not just in memory).
    final s2 = await _store(dir, InMemoryKeyring());
    expect((await s2.unlock('pw')).isOk, isTrue);
    expect(s2.snapshot().valueOrNull!.connections.length, 2);

    await dir.delete(recursive: true);
  });

  test('wrong passphrase yields WrongPassphraseFailure', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final s = await _store(dir, InMemoryKeyring());
    await s.create('right');
    s.lock();
    final r = await s.unlock('wrong');
    expect(r.failureOrNull, isA<WrongPassphraseFailure>());
    await dir.delete(recursive: true);
  });

  test('snapshot while locked yields VaultLockedFailure', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final s = await _store(dir, InMemoryKeyring());
    expect(s.snapshot().failureOrNull, isA<VaultLockedFailure>());
    await dir.delete(recursive: true);
  });

  // Regression: the OS keyring only caches the wrapped key (ADR 0005);
  // passphrase unlock is authoritative. A keyring write failure — e.g. the
  // macOS keychain rejecting the write with errSecMissingEntitlement under
  // ad-hoc signing — must not block vault create/unlock.
  test('create succeeds when the keyring write throws (keyring is best-effort)',
      () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final s = await _store(dir, _ThrowingKeyring());

    final r = await s.create('hunter2');
    expect(r.isOk, isTrue);
    expect(s.isUnlocked, isTrue);
    expect(await s.vaultExists(), isTrue);

    await dir.delete(recursive: true);
  });

  test('unlock succeeds when the keyring write throws (keyring is best-effort)',
      () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    // Create the vault with a working keyring so the file is written.
    final s = await _store(dir, InMemoryKeyring());
    expect((await s.create('hunter2')).isOk, isTrue);

    // Reopen with a keyring that throws on write; unlock must still succeed.
    final s2 = await _store(dir, _ThrowingKeyring());
    final r = await s2.unlock('hunter2');
    expect(r.isOk, isTrue);
    expect(s2.isUnlocked, isTrue);

    await dir.delete(recursive: true);
  });

  // Regression: lock() zeroizes the in-memory data key. If it interleaves with
  // an in-flight mutate, the mutate must NOT (a) seal the vault under the now
  // zeroized key (corruption) nor (b) write _data back, resurrecting plaintext
  // the user asked to drop.
  test('lock() during an in-flight mutate neither corrupts the vault nor '
      'resurrects data', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_lockrace');
    final file = _PausableVaultFile('${dir.path}/vault.bin');
    final s = SecureStore(
        crypto: CryptoService(), file: file, keyring: InMemoryKeyring());
    expect((await s.create('pw')).isOk, isTrue);

    // Seed one connection (this mutate runs before the gate is armed).
    await s.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
                id: 'c1',
                label: 'box',
                host: 'h',
                folderId: null,
                username: 'u',
                port: 22,
                authRef: 'i1',
                tags: [],
                order: 0),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        ));

    // Arm the gate so the NEXT mutate parks inside read(), then start a mutate
    // that would add c2. While it is parked, lock() the store.
    file.hold = Completer<void>();
    final pending = s.mutate((v) => VaultData(
          connections: [
            ...v.connections,
            const Connection(
                id: 'c2',
                label: 'box2',
                host: 'h2',
                folderId: null,
                username: 'u',
                port: 22,
                authRef: 'i1',
                tags: [],
                order: 0),
          ],
          folders: v.folders,
          identities: v.identities,
          pins: v.pins,
        ));
    // Let _mutate run up to the gated read().
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.lock();
    file.hold!.complete(); // release the gated read so the mutate resumes
    final r = await pending;

    // The locked mutate is rejected, not silently applied.
    expect(r.isOk, isFalse);
    // No resurrection: the store stays locked.
    expect(s.snapshot().failureOrNull, isA<VaultLockedFailure>());

    // The vault on disk is NOT corrupted: a fresh instance unlocks with the
    // real passphrase and sees exactly the pre-lock state (c1 only, no c2).
    final s2 = SecureStore(
        crypto: CryptoService(),
        file: VaultFile('${dir.path}/vault.bin'),
        keyring: InMemoryKeyring());
    expect((await s2.unlock('pw')).isOk, isTrue);
    final ids =
        s2.snapshot().valueOrNull!.connections.map((c) => c.id).toList();
    expect(ids, ['c1']);

    await dir.delete(recursive: true);
  });

  test('folder ops persist through mutate and survive reopen', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_ss');
    final s = await _store(dir, InMemoryKeyring());
    expect((await s.create('pw')).isOk, isTrue);

    await s.mutate((v) => addFolder(v, id: 'f1', parentId: null, name: 'work'));
    await s.mutate((v) => setFolderDefaults(v, 'f1', username: 'deploy', port: 22, authRef: 'i1'));

    final s2 = await _store(dir, InMemoryKeyring());
    expect((await s2.unlock('pw')).isOk, isTrue);
    final f = s2.snapshot().valueOrNull!.folders.single;
    expect(f.name, 'work');
    expect(f.username, 'deploy');

    await dir.delete(recursive: true);
  });

  test('reset wipes the vault while unlocked and allows a fresh create',
      () async {
    final dir = await Directory.systemTemp.createTemp('sshall_reset');
    final keyring = InMemoryKeyring();
    final s = await _store(dir, keyring);
    expect((await s.create('hunter2')).isOk, isTrue);
    await keyring.putWrappedKey('cached'); // simulate a cached wrapped key
    expect(s.isUnlocked, isTrue);

    final before = s.revision.value;
    final r = await s.reset();

    expect(r.isOk, isTrue);
    expect(await s.vaultExists(), isFalse);           // file gone
    expect(await keyring.getWrappedKey(), isNull);    // keyring cleared
    expect(s.isUnlocked, isFalse);                    // in-memory dropped
    expect(s.snapshot().failureOrNull, isA<VaultLockedFailure>());
    expect(s.revision.value, greaterThan(before));    // UI notified

    // A brand-new vault can be created on the same path afterwards.
    expect((await s.create('fresh')).isOk, isTrue);
    expect(await s.vaultExists(), isTrue);

    await dir.delete(recursive: true);
  });

  test('reset works while locked (the forgot-passphrase path)', () async {
    final dir = await Directory.systemTemp.createTemp('sshall_reset_locked');
    // Create the vault, then reopen with a FRESH store that is never unlocked —
    // exactly the state of a user who forgot their passphrase.
    final s1 = await _store(dir, InMemoryKeyring());
    expect((await s1.create('pw')).isOk, isTrue);

    final s2 = await _store(dir, InMemoryKeyring());
    expect(s2.isUnlocked, isFalse);
    expect(await s2.vaultExists(), isTrue);

    final r = await s2.reset();

    expect(r.isOk, isTrue);
    expect(await s2.vaultExists(), isFalse);

    await dir.delete(recursive: true);
  });

  test('reset succeeds even when keyring.clear() throws (best-effort)',
      () async {
    final dir = await Directory.systemTemp.createTemp('sshall_reset_keyring');
    final s = await _store(dir, _ThrowingClearKeyring());
    expect((await s.create('pw')).isOk, isTrue);

    final r = await s.reset();

    expect(r.isOk, isTrue);                  // not blocked by keyring failure
    expect(await s.vaultExists(), isFalse);  // file still removed

    await dir.delete(recursive: true);
  });
}

/// A VaultFile whose read() can be parked on a completer, letting a test
/// deterministically interleave another call (e.g. lock()) into the middle of
/// an in-flight mutate.
class _PausableVaultFile extends VaultFile {
  _PausableVaultFile(super.path);
  Completer<void>? hold;

  @override
  Future<Uint8List?> read() async {
    final h = hold;
    if (h != null) await h.future;
    return super.read();
  }
}

/// Simulates an OS keyring that rejects writes (e.g. the macOS keychain
/// returning errSecMissingEntitlement / -34018 for a sandboxed, ad-hoc-signed
/// build). Reads return null; writes throw.
class _ThrowingKeyring implements KeyringStore {
  @override
  Future<void> putWrappedKey(String b64) async =>
      throw Exception('errSecMissingEntitlement (-34018)');

  @override
  Future<String?> getWrappedKey() async => null;

  @override
  Future<void> clear() async {}
}

/// A keyring whose clear() throws — verifies reset() treats keyring clearing as
/// best-effort (ADR 0005) and still removes the authoritative vault file.
class _ThrowingClearKeyring implements KeyringStore {
  String? _value;
  @override
  Future<void> putWrappedKey(String b64) async => _value = b64;
  @override
  Future<String?> getWrappedKey() async => _value;
  @override
  Future<void> clear() async => throw Exception('keyring clear failed');
}
