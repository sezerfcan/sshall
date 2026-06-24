import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/path_breadcrumb.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  group('breadcrumbSegments (pure)', () {
    test('POSIX absolute path → cumulative segments', () {
      final segs = breadcrumbSegments('/home/user/docs');
      expect(segs.map((s) => s.label), ['/', 'home', 'user', 'docs']);
      expect(segs.map((s) => s.path), [
        '/',
        '/home',
        '/home/user',
        '/home/user/docs',
      ]);
    });

    test('remote relative path keeps the "." root', () {
      final segs = breadcrumbSegments('./a/b');
      expect(segs.map((s) => s.label), ['.', 'a', 'b']);
      expect(segs.map((s) => s.path), ['.', './a', './a/b']);
    });

    test('bare "." is a single root segment', () {
      final segs = breadcrumbSegments('.');
      expect(segs.length, 1);
      expect(segs.first.label, '.');
    });
  });

  Widget host(String path, void Function(String) onNav) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: PathBreadcrumb(path: path, onNavigate: onNav),
      ),
    ),
  );

  testWidgets('renders ancestor buttons + bold current segment', (
    tester,
  ) async {
    await tester.pumpWidget(host('/home/user/docs', (_) {}));
    expect(find.text('home'), findsOneWidget);
    expect(find.text('user'), findsOneWidget);
    // Current segment present and rendered via the dedicated key.
    expect(find.byKey(const Key('breadcrumbCurrent')), findsOneWidget);
    expect(
      (tester.widget<Text>(find.byKey(const Key('breadcrumbCurrent'))).data),
      'docs',
    );
  });

  testWidgets('clicking an ancestor navigates to its absolute path', (
    tester,
  ) async {
    String? navigated;
    await tester.pumpWidget(host('/home/user/docs', (p) => navigated = p));
    await tester.tap(find.byKey(const Key('breadcrumbSeg_/home/user')));
    expect(navigated, '/home/user');
  });

  testWidgets('clicking the current segment does NOT navigate', (tester) async {
    String? navigated;
    await tester.pumpWidget(host('/home/user/docs', (p) => navigated = p));
    await tester.tap(find.byKey(const Key('breadcrumbCurrent')));
    await tester.pump();
    expect(navigated, isNull);
  });

  testWidgets('long path collapses leading segments into an … overflow menu', (
    tester,
  ) async {
    String? navigated;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: SizedBox(
            width: 160, // narrow → forces collapse
            child: PathBreadcrumb(
              path: '/a/very/deep/nested/path/here',
              onNavigate: (p) => navigated = p,
            ),
          ),
        ),
      ),
    );
    // The overflow chip exists and the tail (current) stays visible.
    final overflow = find.byKey(const Key('breadcrumbOverflow'));
    expect(overflow, findsOneWidget);
    expect(find.byKey(const Key('breadcrumbCurrent')), findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    // A hidden ancestor is offered in the menu.
    expect(find.text('a'), findsWidgets);
    await tester.tap(find.text('a').last);
    await tester.pumpAndSettle();
    expect(navigated, '/a');
  });

  testWidgets('click-to-edit commits a raw path on Enter', (tester) async {
    String? navigated;
    await tester.pumpWidget(host('/home', (p) => navigated = p));
    await tester.tap(find.byKey(const Key('breadcrumbEditButton')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('breadcrumbEdit'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '/etc/nginx');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(navigated, '/etc/nginx');
  });
}
