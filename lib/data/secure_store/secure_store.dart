import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import '../../services/crypto/crypto_service.dart';
import '../../services/storage/keyring_store.dart';
import '../../services/storage/vault_file.dart';
import '../models/vault_data.dart';

/// Authoritative encrypted vault (ADR 0005). Keyring caches the wrapped key.
class SecureStore {
  final CryptoService crypto;
  final VaultFile file;
  final KeyringStore keyring;

  /// Incremented after every successful create/unlock/mutate so UI can rebuild
  /// reactively via ListenableBuilder(listenable: store.revision).
  final ValueNotifier<int> revision = ValueNotifier(0);

  SecureStore({required this.crypto, required this.file, required this.keyring});

  static const _magic = [0x53, 0x53, 0x48, 0x41, 0x4C]; // "SSHAL"
  static const _version = 1;

  Uint8List? _dataKey; // in-memory only while unlocked
  VaultData? _data;

  // Serializes mutate() calls. Each mutation chains onto the previous one so
  // two concurrent read-modify-write callers cannot both start from the same
  // base snapshot and silently drop one of the writes.
  Future<void> _queue = Future<void>.value();

  bool get isUnlocked => _dataKey != null && _data != null;

  Future<bool> vaultExists() => file.exists();

  Future<Result<void>> create(String masterPassphrase) async {
    try {
      // Never clobber an existing vault: overwriting it would destroy every
      // saved connection/identity/pin irrecoverably. The UI also gates on
      // vaultExists(), but the authoritative method must guard itself.
      if (await file.exists()) {
        return const Err(StorageFailure('Vault already exists'));
      }
      final salt = crypto.randomBytes(16);
      final kek = await crypto.deriveKek(_utf8(masterPassphrase), salt);
      final dataKey = crypto.randomBytes(32);
      final wrapped = await crypto.aeadEncrypt(kek, dataKey);
      final data = VaultData.empty();
      await _persist(salt: salt, wrapped: wrapped, dataKey: dataKey, data: data);
      _dataKey = dataKey;
      _data = data;
      await _cacheWrappedKey(wrapped);
      revision.value++;
      return const Ok(null);
    } catch (_) {
      return const Err(StorageFailure('Could not create vault'));
    }
  }

  Future<Result<void>> unlock(String masterPassphrase) async {
    try {
      final raw = await file.read();
      if (raw == null) return const Err(StorageFailure('No vault file'));
      final parsed = _parse(raw);
      if (parsed == null) return const Err(StorageFailure('Corrupt vault'));
      final kek = await crypto.deriveKek(_utf8(masterPassphrase), parsed.salt);
      final dataKey = await crypto.aeadDecrypt(kek, parsed.wrapped);
      if (dataKey == null) return const Err(WrongPassphraseFailure());
      final plain = await crypto.aeadDecrypt(dataKey, parsed.body);
      if (plain == null) return const Err(StorageFailure('Corrupt vault body'));
      // Decode fully BEFORE publishing _dataKey/_data so a malformed body (a
      // body that authenticates but isn't valid vault JSON) leaves the store
      // cleanly locked instead of half-unlocked.
      final data = VaultData.fromJson(
          jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
      _dataKey = dataKey;
      _data = data;
      await _cacheWrappedKey(parsed.wrapped);
      revision.value++;
      return const Ok(null);
    } catch (_) {
      // deriveKek isolate errors, non-UTF8/non-JSON bodies, schema mismatches —
      // surface a typed failure rather than throwing into the caller (a thrown
      // unlock froze the unlock screen with no error shown).
      return const Err(StorageFailure('Corrupt vault'));
    }
  }

  /// Best-effort cache of the wrapped data key in the OS keyring. The keyring
  /// only caches the wrapped key (ADR 0005); passphrase unlock is the
  /// authoritative path, so a keyring write failure — e.g. the macOS keychain
  /// rejecting the write under ad-hoc signing (errSecMissingEntitlement / -34018)
  /// — must not block create/unlock.
  Future<void> _cacheWrappedKey(Uint8List wrapped) async {
    try {
      await keyring.putWrappedKey(base64.encode(wrapped));
    } catch (_) {
      // Keyring caching is non-essential; ignore failures.
    }
  }

  Future<Result<void>> unlockWithKeyring() async {
    final b64 = await keyring.getWrappedKey();
    if (b64 == null) return const Err(VaultLockedFailure());
    // The wrapped key alone cannot unwrap the data key without the KEK; the
    // keyring path is only meaningful once the OS keyring also stores the
    // unlock token. In this slice the keyring caches presence; passphrase
    // unlock remains the authoritative path.
    return const Err(VaultLockedFailure());
  }

  void lock() {
    // Zeroize the data key bytes before dropping the reference so the plaintext
    // key doesn't linger in the heap until GC.
    final k = _dataKey;
    if (k != null) k.fillRange(0, k.length, 0);
    _dataKey = null;
    _data = null;
    revision.value++;
  }

  Result<VaultData> snapshot() {
    final d = _data;
    if (d == null) return const Err(VaultLockedFailure());
    return Ok(d);
  }

  Future<Result<void>> mutate(VaultData Function(VaultData) update) {
    // Chain this mutation after any in-flight one. `update` then runs against
    // the just-persisted state, never a stale base, so concurrent callers can't
    // lose each other's writes. A failed mutation must not break the chain.
    final result = _queue.then((_) => _mutate(update));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Result<void>> _mutate(VaultData Function(VaultData) update) async {
    try {
      final d = _data;
      final key = _dataKey;
      if (d == null || key == null) return const Err(VaultLockedFailure());
      // Defensive copy of the data key. lock() zeroizes the live _dataKey buffer
      // in place; were it to fire while we await below, encrypting with the live
      // buffer would seal the vault body under an all-zero key — permanently
      // unrecoverable. Encrypt from a private copy so a concurrent lock() cannot
      // corrupt this write. The copy is zeroized as soon as we're done with it.
      final keyCopy = Uint8List.fromList(key);
      final next = update(d);
      final raw = await file.read();
      final parsed = raw == null ? null : _parse(raw);
      if (parsed == null) {
        keyCopy.fillRange(0, keyCopy.length, 0);
        return const Err(StorageFailure('Vault missing'));
      }
      // If lock() ran while we awaited the read, the user asked to drop the
      // plaintext: abort instead of persisting it (and resurrecting _data).
      if (_dataKey == null || _data == null) {
        keyCopy.fillRange(0, keyCopy.length, 0);
        return const Err(VaultLockedFailure());
      }
      await _persist(
          salt: parsed.salt,
          wrapped: parsed.wrapped,
          dataKey: keyCopy,
          data: next);
      keyCopy.fillRange(0, keyCopy.length, 0);
      // A lock() during the persist above leaves a valid on-disk vault (sealed
      // with keyCopy) but the store is now locked — don't resurrect _data.
      if (_dataKey == null || _data == null) return const Ok(null);
      _data = next;
      revision.value++;
      return const Ok(null);
    } catch (_) {
      return const Err(StorageFailure('Could not save vault'));
    }
  }

  /// Destructively wipe the vault and start fresh. Works whether the store is
  /// locked or unlocked — the data key is NOT required. This is the only escape
  /// from a forgotten master passphrase: the vault is zero-knowledge (ADR 0005)
  /// so a forgotten passphrase makes the data unrecoverable; reset deletes
  /// everything instead of recovering it (ADR 0011).
  ///
  /// Chained onto the mutate queue so it cannot race an in-flight mutate()
  /// writing to the file we are about to delete.
  Future<Result<void>> reset() {
    final result = _queue.then((_) => _reset());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Result<void>> _reset() async {
    // Drop in-memory plaintext first: zeroize the data key so it can't linger
    // on the heap, then forget the decoded vault.
    final k = _dataKey;
    if (k != null) k.fillRange(0, k.length, 0);
    _dataKey = null;
    _data = null;
    // Best-effort: the keyring only caches the wrapped key (ADR 0005). A
    // clear() failure must not block the authoritative file deletion.
    try {
      await keyring.clear();
    } catch (_) {/* keyring is a cache; ignore */}
    Result<void> r;
    try {
      await file.delete();
      r = const Ok(null);
    } catch (_) {
      // The on-disk vault could not be removed. In-memory state is already
      // cleared (the store is locked), so we fail safe rather than report a
      // clean wipe.
      r = const Err(StorageFailure('Vault silinemedi'));
    }
    revision.value++;
    return r;
  }

  Future<void> _persist({
    required Uint8List salt,
    required Uint8List wrapped,
    required Uint8List dataKey,
    required VaultData data,
  }) async {
    final body =
        await crypto.aeadEncrypt(dataKey, _utf8(jsonEncode(data.toJson())));
    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(_version);
    out.addByte(salt.length);
    out.add(salt);
    out.addByte((wrapped.length >> 8) & 0xff);
    out.addByte(wrapped.length & 0xff);
    out.add(wrapped);
    out.add(body);
    await file.write(out.toBytes());
  }

  _Parsed? _parse(Uint8List raw) {
    try {
      var o = 0;
      for (var i = 0; i < _magic.length; i++) {
        if (raw[o++] != _magic[i]) return null;
      }
      if (raw[o++] != _version) return null; // unsupported format version
      final saltLen = raw[o++];
      final salt = Uint8List.sublistView(raw, o, o + saltLen);
      o += saltLen;
      final wrappedLen = (raw[o++] << 8) | raw[o++];
      final wrapped = Uint8List.sublistView(raw, o, o + wrappedLen);
      o += wrappedLen;
      final body = Uint8List.sublistView(raw, o);
      return _Parsed(salt, wrapped, body);
    } catch (_) {
      return null;
    }
  }

  Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
}

class _Parsed {
  final Uint8List salt;
  final Uint8List wrapped;
  final Uint8List body;
  _Parsed(this.salt, this.wrapped, this.body);
}
