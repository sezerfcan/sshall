import 'dart:convert';
import 'dart:typed_data';

/// Base64 SHA256 host-key fingerprint digest, without padding or label (ADR
/// 0006). dartssh2's onVerifyHostKey passes [fingerprint] as the UTF-8 bytes of
/// the OpenSSH-style string "SHA256:<base64>", so decode it and strip the label;
/// the dialog and pin storage add the "SHA256:" prefix themselves. Encoding the
/// raw bytes here would double-encode (base64 of "SHA256:...") and produce an
/// un-verifiable fingerprint.
String formatSha256(Uint8List fingerprint) =>
    utf8.decode(fingerprint).replaceFirst('SHA256:', '');
