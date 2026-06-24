import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/services/storage/keyring_store.dart';

void main() {
  test('providers resolve and are overridable', () {
    final container = ProviderContainer(overrides: [
      keyringProvider.overrideWithValue(InMemoryKeyring()),
    ]);
    addTearDown(container.dispose);

    expect(container.read(cryptoServiceProvider), isNotNull);
    expect(container.read(keyringProvider), isA<InMemoryKeyring>());
    expect(container.read(sshServiceProvider), isNotNull);
    expect(container.read(hostKeyCoordinatorProvider), isNotNull);
  });
}
