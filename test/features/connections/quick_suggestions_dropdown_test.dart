import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/features/connections/quick_suggestions.dart';
import 'package:sshall/features/connections/quick_suggestions_dropdown.dart';
import 'package:sshall/theme/app_colors.dart';

/// Widget coverage for the suggestions dropdown (ADR 0034 D4/D6): sectioned
/// recents/saved with type icons, bold match span, per-recent remove, clear
/// history, row tap select, and the highlighted-row visual.
Connection _conn(String id, String label, String host) => Connection(
  id: id,
  label: label,
  host: host,
  folderId: null,
  username: 'root',
  port: 22,
  authRef: 'i$id',
  tags: const [],
  order: 0,
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<Suggestion> suggestions,
    int highlightedIndex = -1,
    void Function(Suggestion)? onSelect,
    void Function(String)? onRemoveRecent,
    VoidCallback? onClearHistory,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.night]),
      home: Scaffold(
        body: QuickSuggestionsDropdown(
          suggestions: suggestions,
          highlightedIndex: highlightedIndex,
          onSelect: onSelect ?? (_) {},
          onRemoveRecent: onRemoveRecent ?? (_) {},
          onClearHistory: onClearHistory ?? () {},
        ),
      ),
    ),
  );

  const recent = Suggestion(
    kind: SuggestionKind.recent,
    display: 'root@a.com:22',
    target: 'root@a.com:22',
  );
  final savedMatch = Suggestion(
    kind: SuggestionKind.saved,
    display: 'my-web-1',
    target: 'root@web.com:22',
    matchStart: 3,
    matchEnd: 6, // "web"
    connection: _conn('1', 'my-web-1', 'web.com'),
  );

  testWidgets('renders both sections with their type icons', (tester) async {
    await pump(tester, suggestions: [recent, savedMatch]);
    expect(find.text('SON BAĞLANANLAR'), findsOneWidget);
    expect(find.text('KAYITLI HOSTLAR'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget); // recent
    expect(find.byIcon(Icons.bookmark_outline), findsOneWidget); // saved
  });

  testWidgets('matched substring is bolded (RichText span)', (tester) async {
    await pump(tester, suggestions: [savedMatch]);
    // The match span lives in our explicit RichText (children: pre/mid/post).
    // Multiple RichText nodes exist (every Text is one), so pick the one whose
    // root TextSpan has a "web" child.
    final boldFinder = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final root = w.text;
      return root is TextSpan &&
          (root.children?.any((s) => s is TextSpan && s.text == 'web') ??
              false);
    });
    final rich = tester.widget<RichText>(boldFinder);
    final spans = (rich.text as TextSpan).children!.cast<TextSpan>();
    final bold = spans.firstWhere((s) => s.text == 'web');
    expect(bold.style!.fontWeight, FontWeight.w700);
  });

  testWidgets('per-recent x calls onRemoveRecent; clear calls onClearHistory', (
    tester,
  ) async {
    String? removed;
    var cleared = false;
    await pump(
      tester,
      suggestions: [recent, savedMatch],
      onRemoveRecent: (t) => removed = t,
      onClearHistory: () => cleared = true,
    );
    await tester.tap(find.byKey(const Key('removeRecent-0')));
    expect(removed, 'root@a.com:22');

    await tester.tap(find.byKey(const Key('clearHistory')));
    expect(cleared, isTrue);
  });

  testWidgets('row tap selects; highlightedIndex tints the row', (
    tester,
  ) async {
    Suggestion? picked;
    await pump(
      tester,
      suggestions: [recent, savedMatch],
      highlightedIndex: 1,
      onSelect: (s) => picked = s,
    );
    await tester.tap(find.byKey(const Key('suggestion-0')));
    expect(picked, recent);

    // The highlighted (index 1) row is tinted with accentSoft.
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('suggestion-1')),
        matching: find.byType(Container),
      ),
    );
    expect((container.color), AppColors.night.accentSoft);
  });
}
