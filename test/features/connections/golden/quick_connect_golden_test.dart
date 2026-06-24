import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/features/connections/quick_connect_bar.dart';
import 'package:sshall/features/connections/quick_suggestions.dart';
import 'package:sshall/features/connections/quick_suggestions_dropdown.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';

/// Golden coverage for the new Quick Connect surfaces (ADR 0034) across all
/// three themes (night / day / terminal): the bar empty (mono placeholder +
/// help icon + leading bolt) and with text (clear x), and the suggestions
/// dropdown (sectioned recents/saved, type icons, bold match, per-recent x).
///
/// No secret ever appears in a golden — recents carry only `user@host:port`.
///
/// Regenerate with:
///   flutter test --update-goldens test/features/connections/golden/quick_connect_golden_test.dart
/// then run without the flag to confirm they pass.
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

QuickConnectBar _bar({List<String> recents = const []}) => QuickConnectBar(
  onConnectTarget: (_) async {},
  recents: recents,
  saved: const [],
  displayOf: (c) => c.label,
  targetOf: (c) => 'root@${c.host}:22',
  hostOf: (c) => c.host,
  onRemoveRecent: (_) {},
  onClearHistory: () {},
);

void main() {
  Widget frame(AppThemeId theme, Widget child, {double width = 520}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appThemeData(theme),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

  final dropdownSuggestions = <Suggestion>[
    const Suggestion(
      kind: SuggestionKind.recent,
      display: 'root@web.example.com:22',
      target: 'root@web.example.com:22',
      matchStart: 5,
      matchEnd: 8, // "web"
    ),
    Suggestion(
      kind: SuggestionKind.saved,
      display: 'web-prod',
      target: 'root@web-prod.com:22',
      matchStart: 0,
      matchEnd: 3, // "web"
      connection: _conn('1', 'web-prod', 'web-prod.com'),
    ),
  ];

  for (final theme in AppThemeId.values) {
    final name = theme.name;

    testWidgets('quick connect bar (empty) — $name', (tester) async {
      await tester.pumpWidget(frame(theme, _bar()));
      await tester.pump();
      await expectLater(
        find.byType(QuickConnectBar),
        matchesGoldenFile('goldens/quick_bar_empty_$name.png'),
      );
    });

    testWidgets('quick connect bar (with text) — $name', (tester) async {
      await tester.pumpWidget(frame(theme, _bar()));
      await tester.enterText(
        find.byKey(const Key('quickConnectInput')),
        'root@db.internal:2222',
      );
      // Drop focus so the suggestions dropdown does not open over the bar.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await expectLater(
        find.byType(QuickConnectBar),
        matchesGoldenFile('goldens/quick_bar_text_$name.png'),
      );
    });

    testWidgets('quick connect suggestions dropdown — $name', (tester) async {
      await tester.pumpWidget(
        frame(
          theme,
          QuickSuggestionsDropdown(
            suggestions: dropdownSuggestions,
            highlightedIndex: 0,
            onSelect: (_) {},
            onRemoveRecent: (_) {},
            onClearHistory: () {},
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(QuickSuggestionsDropdown),
        matchesGoldenFile('goldens/quick_dropdown_$name.png'),
      );
    });
  }
}
