/// A typed success-or-failure value. Services return this instead of throwing.
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}

extension ResultX<T> on Result<T> {
  bool get isOk => this is Ok<T>;
  T? get valueOrNull => switch (this) { Ok(:final value) => value, _ => null };
  Failure? get failureOrNull =>
      switch (this) { Err(:final failure) => failure, _ => null };
}

/// Typed, user-presentable failures. No secret material in [message].
sealed class Failure {
  final String message;
  const Failure(this.message);
}

final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

final class HostKeyMismatchFailure extends Failure {
  const HostKeyMismatchFailure([
    super.message = 'Host key does not match the pinned key (possible MITM)',
  ]);
}

final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network error']);
}

final class VaultLockedFailure extends Failure {
  const VaultLockedFailure([super.message = 'Vault is locked']);
}

final class WrongPassphraseFailure extends Failure {
  const WrongPassphraseFailure([super.message = 'Wrong master passphrase']);
}

final class KeyImportFailure extends Failure {
  const KeyImportFailure([super.message = 'Could not import private key']);
}

final class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Storage error']);
}

final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Unexpected error']);
}
