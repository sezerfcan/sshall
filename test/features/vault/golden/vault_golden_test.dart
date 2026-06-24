import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/host_key_pin.dart';
import 'package:sshall/features/vault/identity_detail.dart';
import 'package:sshall/features/vault/identity_row.dart';
import 'package:sshall/features/vault/identity_view_model.dart';
import 'package:sshall/features/vault/known_hosts_section.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

import '../_identity_fixtures.dart';

/// Golden coverage for the new vault surfaces (ADR 0033) across all three
/// themes (night / day / terminal): the identity list (real algorithm tag +
/// usage badge + truncated fingerprint; password row has NO fingerprint cell),
/// the identity detail (metadata + public-key box + using-connections), and the
/// known-hosts list (pin rows + revoke). The private key is never present in
/// any golden (ADR 0005).
///
/// Regenerate with:
///   flutter test --update-goldens test/features/vault/golden/vault_golden_test.dart
/// then run without the flag to confirm they pass.
void main() {
  Widget frame(AppThemeId theme, Widget child, {double width = 720}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appThemeData(theme),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  final keyView = IdentityView.of(keyIdentity(label: 'prod-server'));
  final pwView = IdentityView.of(passwordIdentity(label: 'db-parola'));

  Connection conn(String label) => Connection(
    id: label,
    label: label,
    host: 'h',
    folderId: null,
    username: null,
    port: null,
    authRef: 'k1',
    tags: const [],
    order: 0,
  );

  for (final theme in AppThemeId.values) {
    final name = theme.name;

    testWidgets('identity list — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IdentityRow(
                view: keyView,
                usage: 2,
                onOpen: () {},
                onAction: (_) {},
              ),
              const SizedBox(height: 8),
              IdentityRow(
                view: pwView,
                usage: 0,
                onOpen: () {},
                onAction: (_) {},
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(Column).first,
        matchesGoldenFile('goldens/identity_list_$name.png'),
      );
    });

    testWidgets('identity detail — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          SingleChildScrollView(
            child: IdentityDetail(
              view: keyView,
              usage: 1,
              referencingConnections: [conn('web1')],
              onRename: () {},
              onDelete: () {},
              onExport: () {},
              onCopyPublicKey: () {},
              onCopyFingerprint: () {},
            ),
          ),
          width: 520,
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(IdentityDetail),
        matchesGoldenFile('goldens/identity_detail_$name.png'),
      );
    });

    testWidgets('known hosts — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          const KnownHostsSection(
            pins: [
              HostKeyPin(
                hostPort: 'web1.example.com:22',
                keyType: 'ssh-ed25519',
                sha256: 'AAAAbbbbCCCCddddEEEEffffGGGGhhhh',
              ),
              HostKeyPin(
                hostPort: 'db.internal:2222',
                keyType: 'ssh-rsa',
                sha256: 'ZZZZyyyyXXXXwwwwVVVVuuuu',
              ),
            ],
            query: '',
            onRevoke: _noop,
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(KnownHostsSection),
        matchesGoldenFile('goldens/known_hosts_$name.png'),
      );
    });
  }
}

void _noop(HostKeyPin _) {}
