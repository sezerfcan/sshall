import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/terminal/connection_error_card.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(body: child),
  );

  ConnectionErrorCard card(
    SessionStatus status, {
    VoidCallback? onRetry,
    VoidCallback? onEdit,
  }) => ConnectionErrorCard(
    status: status,
    hostPort: 'web1:22',
    onRetry: onRetry ?? () {},
    onEdit: onEdit ?? () {},
  );

  group('cause-mapped Turkish title + remedy (D4)', () {
    final cases = <String, ({String code, String msg, String title})>{
      'auth': (
        code: 'auth',
        msg: 'denied',
        title: 'Kimlik doğrulama başarısız',
      ),
      'dns': (
        code: 'network',
        msg: 'Failed host lookup',
        title: 'Ana makine bulunamadı (DNS)',
      ),
      'refused': (
        code: 'network',
        msg: 'Connection refused',
        title: 'Bağlantı reddedildi',
      ),
      'timeout': (
        code: 'network',
        msg: 'Connection timed out',
        title: 'Zaman aşımı',
      ),
      'hostKeyMismatch': (
        code: 'hostkey',
        msg: 'Host key rejected',
        title: 'Ana makine anahtarı DEĞİŞTİ',
      ),
      'unknown': (code: 'weird', msg: 'odd', title: 'Bağlantı hatası'),
    };
    cases.forEach((name, c) {
      testWidgets('$name renders its title', (tester) async {
        await tester.pumpWidget(host(card(classifyError(c.code, c.msg))));
        await tester.pump();
        expect(find.text(c.title), findsOneWidget);
      });
    });
  });

  testWidgets('Detaylar is collapsed initially; expands to show raw mono', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(card(classifyError('network', 'RAW-BOOM-123'))),
    );
    await tester.pump();
    expect(find.byKey(const Key('errorRawMessage')), findsNothing);
    await tester.tap(find.byKey(const Key('errorDetailsToggle')));
    await tester.pump();
    expect(find.byKey(const Key('errorRawMessage')), findsOneWidget);
    expect(find.text('RAW-BOOM-123'), findsOneWidget);
  });

  testWidgets('[Yeniden Dene] → onRetry; [Bağlantıyı Düzenle] → onEdit', (
    tester,
  ) async {
    var retried = false;
    var edited = false;
    await tester.pumpWidget(
      host(
        card(
          classifyError('auth', 'x'),
          onRetry: () => retried = true,
          onEdit: () => edited = true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('errorRetry')));
    expect(retried, isTrue);
    await tester.tap(find.byKey(const Key('errorEdit')));
    expect(edited, isTrue);
  });

  testWidgets('unexpected disconnect → "Bağlantı kesildi" + [Yeniden Bağlan]', (
    tester,
  ) async {
    await tester.pumpWidget(host(card(const SessionStatus.dropped())));
    await tester.pump();
    expect(find.text('Bağlantı kesildi'), findsOneWidget);
    expect(find.text('Yeniden Bağlan'), findsOneWidget);
  });

  testWidgets('hostKeyMismatch uses warning weight (no primary "trust")', (
    tester,
  ) async {
    await tester.pumpWidget(host(card(classifyError('hostkey', 'changed'))));
    await tester.pump();
    expect(find.text('Ana makine anahtarı DEĞİŞTİ'), findsOneWidget);
    expect(find.byIcon(Icons.gpp_maybe_outlined), findsOneWidget);
    // The remedy warns about MITM.
    expect(
      find.text('Sunucu kimliği beklenenle uyuşmuyor — MITM olabilir'),
      findsOneWidget,
    );
  });

  testWidgets('edit action hidden when onEdit is null (Docker exec)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ConnectionErrorCard(
          status: classifyError('auth', 'x'),
          hostPort: '',
          onRetry: () {},
          onEdit: null,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('errorEdit')), findsNothing);
    expect(find.byKey(const Key('errorRetry')), findsOneWidget);
  });
}
