import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds ONLY the wrapped vault data key (ADR 0005). Never plaintext secrets.
abstract class KeyringStore {
  Future<void> putWrappedKey(String b64);
  Future<String?> getWrappedKey();
  Future<void> clear();
}

class SecureStorageKeyring implements KeyringStore {
  static const _key = 'sshall.wrappedDataKey';
  final FlutterSecureStorage _storage;

  SecureStorageKeyring([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> putWrappedKey(String b64) =>
      _storage.write(key: _key, value: b64);

  @override
  Future<String?> getWrappedKey() => _storage.read(key: _key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class InMemoryKeyring implements KeyringStore {
  String? _value;

  @override
  Future<void> putWrappedKey(String b64) async => _value = b64;

  @override
  Future<String?> getWrappedKey() async => _value;

  @override
  Future<void> clear() async => _value = null;
}
