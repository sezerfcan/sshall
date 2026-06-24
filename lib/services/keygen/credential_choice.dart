import '../../data/models/identity.dart';

/// The credential a connect/identity form resolved to, after applying the
/// shared "key vs password" selection rule. Pure value type — no UI, no I/O.
///
/// This collapses an identical decision that lived inline in three places
/// (connect dialog, folder-defaults dialog, saved-connection persistence):
///   secret     = useKey ? pem      : password
///   passphrase = useKey && keyPassphrase.isNotEmpty ? keyPassphrase : null
///   isKey      = useKey
class CredentialChoice {
  /// The PEM (key mode) or the password (password mode). May be null in key
  /// mode when no key has been imported yet; callers validate as needed.
  final String? secret;

  /// Key passphrase, only ever set in key mode and only when non-empty.
  final String? passphrase;

  /// Whether this is a private-key credential (vs a password).
  final bool isKey;

  const CredentialChoice({
    required this.secret,
    required this.passphrase,
    required this.isKey,
  });

  /// [secret] coalesced to '' — for stores that require a non-null secret.
  String get secretOrEmpty => secret ?? '';

  /// The corresponding [IdentityType].
  IdentityType get identityType =>
      isKey ? IdentityType.privateKey : IdentityType.password;
}

/// Applies the shared key-vs-password selection rule to raw form fields.
///
/// In password mode the PEM/key-passphrase inputs are ignored; in key mode the
/// password input is ignored and an empty passphrase is normalised to null.
CredentialChoice credentialFrom({
  required bool useKey,
  required String password,
  required String? pem,
  required String keyPassphrase,
}) =>
    CredentialChoice(
      secret: useKey ? pem : password,
      passphrase: useKey && keyPassphrase.isNotEmpty ? keyPassphrase : null,
      isKey: useKey,
    );
