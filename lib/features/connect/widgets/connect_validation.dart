/// Pure, UI-free validation rules for the "Add Host" connect form (ADR 0031,
/// D5). Each validator returns a Turkish error string, or null when the field
/// is valid. These are deliberately free of Flutter so they can be unit-tested
/// in isolation and reused by the edit dialog (ADR 0025, pass-2).
library;

/// Identifies a form field so the dialog can map an error back to a control and
/// move focus to the FIRST invalid one on submit. Order matters: it mirrors the
/// visual field order (D2) so "first invalid" is also "topmost invalid".
enum ConnectField { label, host, port, credential }

/// Host is required; an empty/whitespace host has nothing to connect to.
String? validateHost(String host) =>
    host.trim().isEmpty ? 'Host boş olamaz.' : null;

/// Label is required: the dialog now always defines a saved host (D1), so every
/// host needs a human-readable name.
String? validateLabel(String label) =>
    label.trim().isEmpty ? 'Etiket boş olamaz.' : null;

/// Port must be an integer in 1–65535. A numeric-but-out-of-range value (e.g.
/// "0") parses fine, so a plain `int.tryParse` is not enough.
String? validatePort(String port) {
  final p = int.tryParse(port.trim());
  if (p == null || p < 1 || p > 65535) {
    return 'Port 1–65535 arası bir sayı olmalı.';
  }
  return null;
}

/// A credential must be provided: either an existing vault identity is selected,
/// or a private key has been imported, or a non-empty password was typed.
///
/// [hasExistingIdentity] — the user picked an existing vault identity.
/// [hasImportedKey]      — a key file was imported (PEM present).
/// [password]            — the typed password (key mode ignores it).
/// [useKey]              — which auth mode is active.
String? validateCredential({
  required bool useKey,
  required bool hasExistingIdentity,
  required bool hasImportedKey,
  required String password,
}) {
  if (useKey) {
    if (hasExistingIdentity || hasImportedKey) return null;
    return 'Bir kimlik seçin veya anahtar dosyası içe aktarın.';
  }
  if (password.isNotEmpty) return null;
  return 'Parola boş olamaz.';
}

/// Aggregates the per-field errors for one submit. Built from the raw field
/// values + the active auth selection. [firstInvalid] is the topmost field with
/// an error (focus target on submit); null when everything is valid.
class ConnectFieldErrors {
  final String? label;
  final String? host;
  final String? port;
  final String? credential;

  const ConnectFieldErrors({this.label, this.host, this.port, this.credential});

  /// Runs every rule against the form snapshot. Field order here defines the
  /// "first invalid" precedence (D2): label → host → port → credential.
  factory ConnectFieldErrors.validate({
    required String label,
    required String host,
    required String port,
    required bool useKey,
    required bool hasExistingIdentity,
    required bool hasImportedKey,
    required String password,
  }) => ConnectFieldErrors(
    label: validateLabel(label),
    host: validateHost(host),
    port: validatePort(port),
    credential: validateCredential(
      useKey: useKey,
      hasExistingIdentity: hasExistingIdentity,
      hasImportedKey: hasImportedKey,
      password: password,
    ),
  );

  bool get isValid =>
      label == null && host == null && port == null && credential == null;

  /// The topmost field with an error, for submit-time focus (D5). null = valid.
  ConnectField? get firstInvalid {
    if (label != null) return ConnectField.label;
    if (host != null) return ConnectField.host;
    if (port != null) return ConnectField.port;
    if (credential != null) return ConnectField.credential;
    return null;
  }

  String? errorFor(ConnectField field) => switch (field) {
    ConnectField.label => label,
    ConnectField.host => host,
    ConnectField.port => port,
    ConnectField.credential => credential,
  };
}
