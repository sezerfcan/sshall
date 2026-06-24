import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/sidebar_empty_states.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: appThemeData(AppThemeId.night),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'first-run state shows icon + title + subtitle + CTA that fires',
    (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _wrap(FirstRunEmptyState(onNewHost: () => fired = true)),
      );
      expect(find.byKey(const Key('sidebar-empty-firstrun')), findsOneWidget);
      expect(find.text('Henüz bağlantı yok'), findsOneWidget);
      expect(
        find.byKey(const Key('sidebar-empty-firstrun-cta')),
        findsOneWidget,
      );
      expect(find.text('Yeni bağlantı'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sidebar-empty-firstrun-cta')));
      expect(fired, isTrue);
    },
  );

  testWidgets('no-results state echoes the query + scope + clears on tap', (
    tester,
  ) async {
    var cleared = false;
    await tester.pumpWidget(
      _wrap(NoSearchResultsState(query: 'foo', onClear: () => cleared = true)),
    );
    expect(find.byKey(const Key('sidebar-empty-noresults')), findsOneWidget);
    expect(find.text('"foo" için sonuç yok'), findsOneWidget);
    expect(
      find.text('Ad, host, etiket veya kullanıcı aranıyor.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sidebar-empty-noresults-clear')));
    expect(cleared, isTrue);
  });

  testWidgets('empty-folder hint is an indented inline drag invitation', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const EmptyFolderHint(depth: 0)));
    expect(find.byKey(const Key('sidebar-empty-folder-hint')), findsOneWidget);
    expect(find.text('Boş klasör — buraya host sürükleyin'), findsOneWidget);
  });

  testWidgets('the three states render DISTINCT content (no shared "Kayıt yok")', (
    tester,
  ) async {
    // First-run carries a CTA; no-results carries echo + clear; empty-folder is
    // an inline hint. None of them is the old shared "Kayıt yok"/"Eşleşme yok".
    await tester.pumpWidget(_wrap(FirstRunEmptyState(onNewHost: () {})));
    expect(find.text('Kayıt yok'), findsNothing);
    expect(find.text('Eşleşme yok'), findsNothing);

    await tester.pumpWidget(
      _wrap(NoSearchResultsState(query: 'x', onClear: () {})),
    );
    expect(find.text('Aramayı temizle'), findsOneWidget);
    expect(find.text('Henüz bağlantı yok'), findsNothing);
  });
}
