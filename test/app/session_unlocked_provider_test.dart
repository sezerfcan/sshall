import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';

void main() {
  test('sessionUnlockedProvider defaults to locked and can toggle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Defaults to locked so a cold start shows the unlock screen.
    expect(container.read(sessionUnlockedProvider), isFalse);

    container.read(sessionUnlockedProvider.notifier).state = true;
    expect(container.read(sessionUnlockedProvider), isTrue);

    // Reset flips it back to locked (the settings danger-zone path).
    container.read(sessionUnlockedProvider.notifier).state = false;
    expect(container.read(sessionUnlockedProvider), isFalse);
  });
}
