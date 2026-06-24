import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/connect/host_key_dialog.dart';
import 'package:sshall/theme/app_colors.dart';

/// The host-key dialog is the single most safety-critical decision a user makes
/// ("trust / reject"). Its title and the MITM warning must be in Turkish so the
/// user actually understands the risk instead of blindly trusting — keeping the
/// language consistent with the Turkish action buttons.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required bool mismatch,
    String? oldSha256,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showHostKeyDialog(
                  context,
                  hostPort: 'example.com:22',
                  keyType: 'ssh-ed25519',
                  sha256: 'abc123',
                  mismatch: mismatch,
                  oldSha256: oldSha256,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('mismatch title and MITM warning are Turkish', (tester) async {
    await open(tester, mismatch: true);
    expect(find.text('Host anahtarı değişti'), findsOneWidget);
    expect(find.textContaining('EŞLEŞMİYOR'), findsOneWidget);
    expect(find.textContaining('ortadaki-adam'), findsOneWidget);
    // No leftover English copy.
    expect(find.text('Host key changed'), findsNothing);
    expect(find.textContaining('man-in-the-middle'), findsNothing);
  });

  testWidgets('verify (first-pin) title is Turkish', (tester) async {
    await open(tester, mismatch: false);
    expect(find.text('Host anahtarını doğrula'), findsOneWidget);
    expect(find.text('Verify host key'), findsNothing);
  });

  testWidgets('mismatch shows BOTH the old (pinned) and new fingerprints', (
    tester,
  ) async {
    // On a mismatch the user must compare the previously trusted key against the
    // newly presented one to make an informed MITM decision — not just see the
    // new one. Both fingerprints, clearly labelled old vs new, must be visible.
    await open(tester, mismatch: true, oldSha256: 'OLDpinned999');
    expect(find.textContaining('OLDpinned999'), findsOneWidget); // old pin
    expect(find.textContaining('abc123'), findsOneWidget); // newly presented
    // Labelled so the user can tell which is which.
    expect(find.textContaining('Sabitlenen'), findsOneWidget); // pinned/old
    expect(find.textContaining('Sunucunun sunduğu'), findsOneWidget); // new
  });

  testWidgets('mismatch without an old fingerprint omits the old row', (
    tester,
  ) async {
    // Defensive: if the old pin is somehow unavailable, the dialog still works
    // and just shows the new key (no empty "old" row).
    await open(tester, mismatch: true, oldSha256: null);
    expect(find.textContaining('abc123'), findsOneWidget);
    expect(find.textContaining('Sabitlenen'), findsNothing);
  });
}
