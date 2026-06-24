import 'dart:convert';
import 'dart:typed_data';

import '../../data/models/identity.dart';
import '../../services/keygen/key_generator.dart';

/// A pure, UI-less projection of an [Identity] that surfaces only NON-SECRET
/// material (ADR 0033 / D1): the one-line public key, the canonical SHA256
/// fingerprint, and a human-readable algorithm label. The private key
/// (`secret` PEM) and passphrase are NEVER read into this view.
///
/// Resolution order for the public key / fingerprint:
///   1. the values persisted at generation (fast path), else
///   2. derived lazily from the stored PEM (legacy/imported), else
///   3. null (password identities, or an encrypted/corrupt PEM).
class IdentityView {
  final Identity identity;

  /// One-line authorized_keys public key, or null (password / underivable).
  final String? publicKeyOpenSSH;

  /// Canonical "SHA256:..." fingerprint, or null (password / underivable).
  final String? fingerprint;

  /// e.g. "ED25519", "RSA 4096", "ECDSA nistp256". Falls back to "Anahtar"
  /// when the algorithm cannot be determined (encrypted/corrupt key), and is
  /// "Parola" for password identities.
  final String algorithmLabel;

  const IdentityView({
    required this.identity,
    required this.publicKeyOpenSSH,
    required this.fingerprint,
    required this.algorithmLabel,
  });

  bool get isKey => identity.type == IdentityType.privateKey;

  /// True when there is a fingerprint to show (a real, derivable key). Password
  /// rows have no fingerprint cell (D2 — no dead '—').
  bool get hasFingerprint => fingerprint != null;

  /// Builds the view for [identity]. [deriver] lets tests inject a derivation;
  /// in production it defaults to [KeyGenerator.deriveFromPem].
  factory IdentityView.of(
    Identity identity, {
    PublicKeyInfo? Function(String pem)? deriver,
  }) {
    if (identity.type == IdentityType.password) {
      return IdentityView(
        identity: identity,
        publicKeyOpenSSH: null,
        fingerprint: null,
        algorithmLabel: 'Parola',
      );
    }

    var publicKey = identity.publicKeyOpenSSH;
    var fingerprint = identity.fingerprint;

    // Legacy/imported keys lack persisted public material → derive from the PEM.
    if (publicKey == null || fingerprint == null) {
      final derive = deriver ?? (pem) => KeyGenerator.deriveFromPem(pem);
      final info = derive(identity.secret);
      if (info != null) {
        publicKey ??= info.publicKeyOpenSSH;
        fingerprint ??= info.fingerprint;
      }
    }

    return IdentityView(
      identity: identity,
      publicKeyOpenSSH: publicKey,
      fingerprint: fingerprint,
      algorithmLabel: _algorithmLabel(publicKey),
    );
  }
}

/// Derives a human-readable algorithm label from a one-line OpenSSH public key.
/// Returns "Anahtar" (generic key) when [publicKey] is null or unparseable.
String _algorithmLabel(String? publicKey) {
  if (publicKey == null) return 'Anahtar';
  final parts = publicKey.split(' ');
  if (parts.length < 2) return 'Anahtar';
  final type = parts[0];
  Uint8List wire;
  try {
    wire = base64.decode(parts[1]);
  } catch (_) {
    return 'Anahtar';
  }
  if (type == 'ssh-ed25519') return 'ED25519';
  if (type == 'ssh-rsa') {
    final bits = _rsaBits(wire);
    return bits == null ? 'RSA' : 'RSA $bits';
  }
  if (type.startsWith('ecdsa-sha2-')) {
    final curve = _ecdsaCurve(wire);
    return curve == null ? 'ECDSA' : 'ECDSA $curve';
  }
  return 'Anahtar';
}

/// Reads the RSA modulus bit length from an "ssh-rsa" wire blob.
/// Layout: string "ssh-rsa", mpint e, mpint n. The modulus bit count is the
/// key size (rounded up to the canonical 2048/3072/4096 sizes by callers).
int? _rsaBits(Uint8List wire) {
  try {
    final r = _WireReader(wire);
    r.readString(); // "ssh-rsa"
    r.readString(); // e
    final n = r.readString(); // modulus
    return _mpintBitLength(n);
  } catch (_) {
    return null;
  }
}

/// Reads the curve identifier (e.g. "nistp256") from an ecdsa wire blob.
/// Layout: string "ecdsa-sha2-<curve>", string "<curve>", string Q.
String? _ecdsaCurve(Uint8List wire) {
  try {
    final r = _WireReader(wire);
    r.readString(); // "ecdsa-sha2-nistpXXX"
    return utf8.decode(r.readString());
  } catch (_) {
    return null;
  }
}

/// Bit length of an SSH mpint (big-endian, possibly with a leading 0x00 sign
/// pad). Strips leading zero bytes, then counts the bits of the top byte.
int _mpintBitLength(Uint8List bytes) {
  var i = 0;
  while (i < bytes.length && bytes[i] == 0) {
    i++;
  }
  if (i >= bytes.length) return 0;
  var bits = (bytes.length - i - 1) * 8;
  var top = bytes[i];
  while (top > 0) {
    bits++;
    top >>= 1;
  }
  return bits;
}

/// Minimal reader for SSH "string" fields (uint32 length + bytes).
class _WireReader {
  final Uint8List _data;
  int _pos = 0;
  _WireReader(this._data);

  Uint8List readString() {
    final len =
        (_data[_pos] << 24) |
        (_data[_pos + 1] << 16) |
        (_data[_pos + 2] << 8) |
        _data[_pos + 3];
    _pos += 4;
    final out = _data.sublist(_pos, _pos + len);
    _pos += len;
    return out;
  }
}
