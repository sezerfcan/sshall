import 'package:sshall/data/models/identity.dart';

/// Real, generation-consistent NON-SECRET public key + fingerprint pairs,
/// captured once from KeyGenerator (ED25519 / RSA-2048). Using literals lets
/// widget/golden tests build identities with PERSISTED public material so
/// IdentityView.of never has to parse a PEM through an isolate (which does not
/// complete under the widget tester's fake clock). The `secret` is a dummy
/// non-PEM string — these fixtures never exercise derivation.

const edPub =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJP540YYY9FSmIXgq7VYJZ0gSnqQa1UA1NaUi4AkL5u fix@sshall';
const edFp = 'SHA256:XdRpOOvmGzLupxwhIiWywDbBe3iHwYpxKSCQoSPUPuw';

const rsaPub =
    'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC2VmvZhLj0Drw/3/SXhyjMOyHN9tAhNaX6CeRO9DRvSt8HZy7aFQSmXawbxZU0CwlsWjtb1qWaw2pn2W3xehm9zgfzKWtrAVyqOdHN71DgZA+CNsJuSUp9ZcPs4eRR93Io0n4WjVq4tuYlNmmD5vCqiCAyImGwazja9IQR+Mk2UfvGTrhg0EO//bsYMuvdDCSqKXP3DJdonkrqNM/tnjngX8/krqw0Hj6YinCCOxYYgBmkLmjV//tkg3T8jT6gT1OEvd1aVx0+TqiGuby5rUTQbZZht9mt1MKqsijR86maOCnj51daOmuhHPVWfNSRP9NzhUOJGdijyhz+nYzvszdT fix@sshall';
const rsaFp = 'SHA256:4isjGb8XMhU7eS/xt8qC1ZXENuiKjaIynW4Dd4y6HFY';

/// A private-key Identity whose public material is PERSISTED (no derivation).
/// [secret] is a marker the tests assert is never rendered (ADR 0005).
Identity keyIdentity({
  String id = 'k1',
  String label = 'prod-key',
  String publicKey = edPub,
  String fingerprint = edFp,
  String secret = 'PRIVATE-PEM-NEVER-SHOWN',
  int? createdAt = 1700000000000,
}) => Identity(
  id: id,
  label: label,
  type: IdentityType.privateKey,
  secret: secret,
  passphrase: null,
  publicKeyOpenSSH: publicKey,
  fingerprint: fingerprint,
  createdAt: createdAt,
);

Identity passwordIdentity({
  String id = 'p1',
  String label = 'db-pw',
  String secret = 'PASSWORD-NEVER-SHOWN',
}) => Identity(
  id: id,
  label: label,
  type: IdentityType.password,
  secret: secret,
  passphrase: null,
);
