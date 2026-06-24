import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/connecting_pane.dart';
import 'package:sshall/features/terminal/connection_error_card.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/terminal_status_bar.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/app_colors.dart';

/// Golden coverage for the new connection-status surfaces (ADR 0032 D8) across
/// all three themes (night / day / terminal). Verifies the amber/warning token,
/// the localized labels, and the cause-mapped error card render correctly.
///
/// Regenerate with:
///   flutter test --update-goldens \
///     test/features/terminal/golden/connection_status_golden_test.dart
/// then run without the flag to confirm they pass.
void main() {
  Widget frame(AppThemeId theme, Widget child, {double height = 120}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appThemeData(theme),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 520, height: height, child: child),
          ),
        ),
      );

  TerminalStatusBar bar(SessionStatus status, {String? cipher}) =>
      TerminalStatusBar(
        status: status,
        hostPort: 'web1:22',
        cipher: cipher,
        fontSize: 13,
        onReconnect: () {},
        onZoomIn: () {},
        onZoomOut: () {},
        onZoomReset: () {},
      );

  for (final theme in AppThemeId.values) {
    final name = theme.name;

    testWidgets('status bar — connected — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          bar(const SessionStatus.connected(), cipher: 'aes256-gcm'),
          height: 28,
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(TerminalStatusBar),
        matchesGoldenFile('goldens/status_bar_connected_$name.png'),
      );
    });

    testWidgets('status bar — connecting — $name', (tester) async {
      await tester.pumpWidget(
        frame(theme, bar(const SessionStatus.connecting()), height: 28),
      );
      await tester.pump();
      await expectLater(
        find.byType(TerminalStatusBar),
        matchesGoldenFile('goldens/status_bar_connecting_$name.png'),
      );
    });

    testWidgets('status bar — error — $name', (tester) async {
      await tester.pumpWidget(
        frame(theme, bar(classifyError('auth', 'denied')), height: 28),
      );
      await tester.pump();
      await expectLater(
        find.byType(TerminalStatusBar),
        matchesGoldenFile('goldens/status_bar_error_$name.png'),
      );
    });

    testWidgets('connecting pane — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          ConnectingPane(
            status: const SessionStatus.connecting(),
            hostPort: 'web1:22',
            onCancel: () {},
          ),
          height: 220,
        ),
      );
      // Settle the indeterminate spinner to a fixed phase for determinism.
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(ConnectingPane),
        matchesGoldenFile('goldens/connecting_pane_$name.png'),
      );
    });

    testWidgets('error card — auth — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          ConnectionErrorCard(
            status: classifyError('auth', 'Authentication failed'),
            hostPort: 'web1:22',
            onRetry: () {},
            onEdit: () {},
          ),
          height: 360,
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(ConnectionErrorCard),
        matchesGoldenFile('goldens/error_card_auth_$name.png'),
      );
    });

    testWidgets('error card — host-key mismatch (warning) — $name', (
      tester,
    ) async {
      await tester.pumpWidget(
        frame(
          theme,
          ConnectionErrorCard(
            status: classifyError('hostkey', 'Host key rejected'),
            hostPort: 'web1:22',
            onRetry: () {},
            onEdit: () {},
          ),
          height: 360,
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(ConnectionErrorCard),
        matchesGoldenFile('goldens/error_card_hostkey_$name.png'),
      );
    });
  }
}
