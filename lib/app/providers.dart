import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/secure_store/secure_store.dart';
import '../services/crypto/crypto_service.dart';
import '../services/keygen/key_generator.dart';
import '../services/ssh/host_key_coordinator.dart';
import '../services/ssh/ssh_service.dart';
import '../services/storage/keyring_store.dart';
import '../services/storage/vault_file.dart';

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final keyGeneratorProvider = Provider<KeyGenerator>((ref) => KeyGenerator());

final keyringProvider =
    Provider<KeyringStore>((ref) => SecureStorageKeyring());

final sshServiceProvider = Provider<SshService>((ref) => SshService());

final hostKeyCoordinatorProvider =
    Provider<HostKeyCoordinator>((ref) => HostKeyCoordinator());

final vaultPathProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/vault.bin';
});

final secureStoreProvider = FutureProvider<SecureStore>((ref) async {
  final path = await ref.watch(vaultPathProvider.future);
  return SecureStore(
    crypto: ref.watch(cryptoServiceProvider),
    file: VaultFile(path),
    keyring: ref.watch(keyringProvider),
  );
});
