import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/status_colors.dart';
import 'package:sshall/features/terminal/terminal_status_bar.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: child),
  );

  TerminalStatusBar bar(
    SessionStatus status, {
    String hostPort = 'web1:22',
    String? cipher,
    VoidCallback? onReconnect,
  }) => TerminalStatusBar(
    status: status,
    hostPort: hostPort,
    cipher: cipher,
    fontSize: 13,
    onReconnect: onReconnect,
    onZoomIn: () {},
    onZoomOut: () {},
    onZoomReset: () {},
  );

  testWidgets('renders real host:port (not empty)', (tester) async {
    await tester.pumpWidget(host(bar(const SessionStatus.connected())));
    await tester.pump();
    expect(find.text('web1:22'), findsOneWidget);
  });

  testWidgets('shows cipher only when connected + provided', (tester) async {
    await tester.pumpWidget(
      host(bar(const SessionStatus.connected(), cipher: 'aes256-gcm')),
    );
    await tester.pump();
    expect(find.text('aes256-gcm'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('status label is Turkish, not a raw English token', (
    tester,
  ) async {
    await tester.pumpWidget(host(bar(const SessionStatus.connected())));
    await tester.pump();
    expect(find.text('Bağlı'), findsOneWidget);
    expect(find.text('ready'), findsNothing);
    expect(find.text('connected'), findsNothing);
  });

  testWidgets('dot color maps to status (connected=green, error=red, '
      'connecting=amber)', (tester) async {
    for (final entry in <SessionStatus, Color>{
      const SessionStatus.connected(): AppColors.night.green,
      classifyError('auth', 'x'): AppColors.night.red,
      const SessionStatus.connecting(): AppColors.night.amber,
    }.entries) {
      await tester.pumpWidget(host(bar(entry.key)));
      await tester.pump();
      final expected = statusColorOf(entry.key, AppColors.night);
      expect(expected, entry.value);
    }
  });

  testWidgets('reconnect affordance: hidden when connected, shown + tappable '
      'on error/disconnect (D7)', (tester) async {
    var clicks = 0;
    // Connected → no reconnect affordance.
    await tester.pumpWidget(
      host(bar(const SessionStatus.connected(), onReconnect: () => clicks++)),
    );
    await tester.pump();
    expect(find.byKey(const Key('statusReconnect')), findsNothing);

    // Error → clickable reconnect.
    await tester.pumpWidget(
      host(
        bar(
          classifyError('network', 'Connection refused'),
          onReconnect: () => clicks++,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('statusReconnect')), findsOneWidget);
    expect(find.text('Yeniden bağlan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statusReconnect')));
    expect(clicks, 1);

    // Unexpected disconnect → clickable reconnect.
    await tester.pumpWidget(
      host(bar(const SessionStatus.dropped(), onReconnect: () => clicks++)),
    );
    await tester.pump();
    expect(find.byKey(const Key('statusReconnect')), findsOneWidget);
  });

  testWidgets('zoom controls remain on the right', (tester) async {
    await tester.pumpWidget(host(bar(const SessionStatus.connected())));
    await tester.pump();
    expect(find.byKey(const Key('zoomIn')), findsOneWidget);
    expect(find.byKey(const Key('zoomOut')), findsOneWidget);
    expect(find.byKey(const Key('zoomReset')), findsOneWidget);
    expect(find.text('13pt'), findsOneWidget);
  });
}
