import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/match_highlight.dart';
import 'package:sshall/features/shell/shell_metrics.dart';
import 'package:sshall/features/shell/sidebar_empty_states.dart';
import 'package:sshall/features/shell/sidebar_row.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/context_ext.dart';

/// Golden coverage for the new connection-tree surfaces (ADR 0035): the three
/// distinct empty states, a row with a match highlight, and the drop indicators
/// (insertion line + move-into highlight) rendered in isolation — across the
/// three themes (night / day / terminal). Regenerate with:
///   flutter test --update-goldens test/features/shell/connection_tree_golden_test.dart
/// then run without the flag to confirm they pass.
const _themes = AppThemeId.values;

Future<void> _frame(WidgetTester tester, AppThemeId theme, Widget child) async {
  tester.view.physicalSize = const Size(272, 320);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appThemeData(theme),
      home: Scaffold(body: SizedBox(width: 272, child: child)),
    ),
  );
  await tester.pump();
}

/// A static demonstration of the drop indicators: a host row with a 2px accent
/// insertion line at its bottom edge, and a folder row in the move-into state
/// (accent outline + soft fill) — distinct from the selected state shown above.
class _DropIndicatorDemo extends StatelessWidget {
  const _DropIndicatorDemo();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget rowText(String s, {Color? color, FontWeight? w}) => Text(
      s,
      style: context.ui(
        size: 12.5,
        color: color ?? c.text,
        weight: w ?? FontWeight.w400,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selected row (fill only) — the visual the move-into must be DISTINCT
        // from.
        SidebarRow(
          selected: true,
          onTap: () {},
          indent: ShellMetrics.sidebarBaseIndent,
          child: rowText('selected-host', color: c.accent, w: FontWeight.w600),
        ),
        // Reorder insertion line at the bottom edge (after-zone) of a host.
        Stack(
          children: [
            SidebarRow(
              onTap: () {},
              indent: ShellMetrics.sidebarBaseIndent,
              child: rowText('reorder-host'),
            ),
            Positioned(
              left: ShellMetrics.sidebarBaseIndent + 2,
              right: 6,
              bottom: 2,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
        // Move-into highlight: accent outline + soft fill (DISTINCT from selected).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Container(
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(ShellMetrics.rowRadius),
              border: Border.all(color: c.accent, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ShellMetrics.sidebarBaseIndent,
                ShellMetrics.rowVerticalPadding,
                8,
                ShellMetrics.rowVerticalPadding,
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 14, color: c.textMuted),
                  const SizedBox(width: 7),
                  rowText('drop-into-folder'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row whose label has its matched substring accent-tinted + bold.
class _MatchHighlightDemo extends StatelessWidget {
  const _MatchHighlightDemo();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = context.ui(size: 12.5, color: c.text);
    final hit = context.ui(
      size: 12.5,
      color: c.accent,
      weight: FontWeight.w700,
    );
    return SidebarRow(
      onTap: () {},
      indent: ShellMetrics.sidebarBaseIndent,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.textDim, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: highlightMatch(
                  'web-deploy-1',
                  'deploy',
                  base: base,
                  hit: hit,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  for (final theme in _themes) {
    final name = theme.name;

    testWidgets('tree golden — first-run empty ($name)', (tester) async {
      await _frame(tester, theme, FirstRunEmptyState(onNewHost: () {}));
      await expectLater(
        find.byType(FirstRunEmptyState),
        matchesGoldenFile('goldens/tree_firstrun_$name.png'),
      );
    });

    testWidgets('tree golden — no-results empty ($name)', (tester) async {
      await _frame(
        tester,
        theme,
        NoSearchResultsState(query: 'foo', onClear: () {}),
      );
      await expectLater(
        find.byType(NoSearchResultsState),
        matchesGoldenFile('goldens/tree_noresults_$name.png'),
      );
    });

    testWidgets('tree golden — empty-folder hint ($name)', (tester) async {
      await _frame(
        tester,
        theme,
        const Align(
          alignment: Alignment.topLeft,
          child: EmptyFolderHint(depth: 0),
        ),
      );
      await expectLater(
        find.byType(EmptyFolderHint),
        matchesGoldenFile('goldens/tree_emptyfolder_$name.png'),
      );
    });

    testWidgets('tree golden — match highlight row ($name)', (tester) async {
      await _frame(
        tester,
        theme,
        const Align(alignment: Alignment.topLeft, child: _MatchHighlightDemo()),
      );
      await expectLater(
        find.byType(_MatchHighlightDemo),
        matchesGoldenFile('goldens/tree_match_highlight_$name.png'),
      );
    });

    testWidgets('tree golden — drop indicators ($name)', (tester) async {
      await _frame(
        tester,
        theme,
        const Align(alignment: Alignment.topLeft, child: _DropIndicatorDemo()),
      );
      await expectLater(
        find.byType(_DropIndicatorDemo),
        matchesGoldenFile('goldens/tree_drop_indicators_$name.png'),
      );
    });
  }
}
