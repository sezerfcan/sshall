/// Sentinel for [Identity.copyWith] so an explicit `null` argument can clear a
/// nullable field, distinct from "argument omitted → keep current value".
const Object _sentinel = Object();

enum IdentityType { password, privateKey }

class Identity {
  final String id;
  final String label;
  final IdentityType type;

  /// Password text (type==password) or PEM private key (type==privateKey).
  final String secret;

  /// Key passphrase for an encrypted private key, else null.
  final String? passphrase;

  // ── NON-SECRET fields (ADR 0033 / D1) ────────────────────────────────────
  // The public key + fingerprint are NOT secrets (PuTTYgen / 1Password show
  // them freely). Storing/displaying them does NOT violate ADR 0005; the
  // private key (`secret` PEM) + `passphrase` remain the only protected values.
  // All three are nullable: legacy/imported identities lack them and derive the
  // public key + fingerprint lazily from the stored PEM (KeyGenerator.deriveFromPem).

  /// One-line authorized_keys format: "<type> <base64> <comment>".
  final String? publicKeyOpenSSH;

  /// Canonical "SHA256:<base64-without-padding>" (same format the key generator
  /// emits and the host-key layer compares against).
  final String? fingerprint;

  /// Creation timestamp, epoch milliseconds. Null for legacy records.
  final int? createdAt;

  const Identity({
    required this.id,
    required this.label,
    required this.type,
    required this.secret,
    required this.passphrase,
    this.publicKeyOpenSSH,
    this.fingerprint,
    this.createdAt,
  });

  /// Returns a copy with the given fields replaced. For the nullable non-secret
  /// fields, omitting the argument keeps the current value (sentinel); passing
  /// `null` explicitly clears it. [label] rename is the common path (CRUD D4).
  Identity copyWith({
    String? label,
    Object? publicKeyOpenSSH = _sentinel,
    Object? fingerprint = _sentinel,
    Object? createdAt = _sentinel,
  }) => Identity(
    id: id,
    label: label ?? this.label,
    type: type,
    secret: secret,
    passphrase: passphrase,
    publicKeyOpenSSH: identical(publicKeyOpenSSH, _sentinel)
        ? this.publicKeyOpenSSH
        : publicKeyOpenSSH as String?,
    fingerprint: identical(fingerprint, _sentinel)
        ? this.fingerprint
        : fingerprint as String?,
    createdAt: identical(createdAt, _sentinel)
        ? this.createdAt
        : createdAt as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'secret': secret,
    'passphrase': passphrase,
    // Only emit the non-secret keys when present, keeping old vaults lean
    // and round-trip stable for records that never had them.
    if (publicKeyOpenSSH != null) 'publicKeyOpenSSH': publicKeyOpenSSH,
    if (fingerprint != null) 'fingerprint': fingerprint,
    if (createdAt != null) 'createdAt': createdAt,
  };

  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
    id: j['id'] as String,
    label: j['label'] as String,
    type: IdentityType.values.byName(j['type'] as String),
    secret: j['secret'] as String,
    passphrase: j['passphrase'] as String?,
    // Backward-compatible: old records lack these keys → null.
    publicKeyOpenSSH: j['publicKeyOpenSSH'] as String?,
    fingerprint: j['fingerprint'] as String?,
    createdAt: j['createdAt'] as int?,
  );
}
