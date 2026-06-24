class HostKeyPin {
  /// "host:port" key.
  final String hostPort;
  final String keyType;

  /// Base64 SHA256 fingerprint (no padding), matching dartssh2's callback.
  final String sha256;

  const HostKeyPin({
    required this.hostPort,
    required this.keyType,
    required this.sha256,
  });

  Map<String, dynamic> toJson() => {
        'hostPort': hostPort,
        'keyType': keyType,
        'sha256': sha256,
      };

  factory HostKeyPin.fromJson(Map<String, dynamic> j) => HostKeyPin(
        hostPort: j['hostPort'] as String,
        keyType: j['keyType'] as String,
        sha256: j['sha256'] as String,
      );
}
