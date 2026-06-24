import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/connecting_pane.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/features/terminal/status_colors.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: child),
  );

  testWidgets('connecting phase shows host:port phrasing + spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ConnectingPane(
          status: const SessionStatus.connecting(),
          hostPort: 'web1:22',
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('web1:22 adresine bağlanılıyor…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('authenticating phase shows "Kimlik doğrulanıyor…"', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ConnectingPane(
          status: const SessionStatus.authenticating(),
          hostPort: 'web1:22',
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Kimlik doğrulanıyor…'), findsOneWidget);
  });

  testWidgets('İptal triggers onCancel', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      host(
        ConnectingPane(
          status: const SessionStatus.connecting(),
          hostPort: 'web1:22',
          onCancel: () => cancelled = true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('connectingCancel')));
    expect(cancelled, isTrue);
  });

  testWidgets('spinner is amber, not gray (D8)', (tester) async {
    await tester.pumpWidget(
      host(
        ConnectingPane(
          status: const SessionStatus.connecting(),
          hostPort: 'web1:22',
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    final amber = statusColor(SessionState.connecting, null, AppColors.night);
    expect(spinner.valueColor!.value, amber);
    expect(spinner.valueColor!.value, isNot(AppColors.night.textDim));
  });

  testWidgets('cancel control is discoverable via tooltip (§9)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ConnectingPane(
          status: const SessionStatus.connecting(),
          hostPort: 'web1:22',
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byTooltip('Bağlanmayı iptal et ve sekmeyi kapat'),
      findsOneWidget,
    );
  });
}
