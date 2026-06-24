import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import 'quick_suggestions.dart';

/// The omnibox suggestions dropdown (ADR 0034 D4/D6): an elevated surface flush
/// to the Quick Connect bar, sectioned into "SON BAĞLANANLAR" (recents) and
/// "KAYITLI HOSTLAR" (saved hosts), each row carrying a leading type icon
/// (clock = recent, bookmark = saved) with the matched substring bolded.
/// Recents rows carry a trailing remove (x); a "Geçmişi temizle" action clears
/// all recents.
///
/// [highlightedIndex] indexes into [suggestions] (the FLAT, already-ordered list
/// the bar keeps for keyboard navigation) so the visually highlighted row stays
/// in sync with Up/Down. Per §9 the type icons + the clear-history tooltip make
/// the surface self-explanatory.
class QuickSuggestionsDropdown extends StatelessWidget {
  final List<Suggestion> suggestions;
  final int highlightedIndex;
  final ValueChanged<Suggestion> onSelect;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearHistory;

  const QuickSuggestionsDropdown({
    super.key,
    required this.suggestions,
    required this.highlightedIndex,
    required this.onSelect,
    required this.onRemoveRecent,
    required this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final recents = <int>[];
    final saved = <int>[];
    for (var i = 0; i < suggestions.length; i++) {
      (suggestions[i].kind == SuggestionKind.recent ? recents : saved).add(i);
    }

    final hasRecents = recents.isNotEmpty;

    return Container(
      key: const Key('quickSuggestionsDropdown'),
      decoration: BoxDecoration(
        color: c.elevated,
        // Flush to the bar: square the top corners, round the bottom.
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasRecents) ...[
            _sectionHeader(
              context,
              'SON BAĞLANANLAR',
              trailing: Tooltip(
                message: 'Tüm hızlı bağlanma geçmişini temizle',
                child: GestureDetector(
                  key: const Key('clearHistory'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onClearHistory,
                  child: Text(
                    'Geçmişi temizle',
                    style: context.ui(
                      size: 11,
                      weight: FontWeight.w600,
                      color: c.accent,
                    ),
                  ),
                ),
              ),
            ),
            for (final i in recents) _row(context, i),
          ],
          if (saved.isNotEmpty) ...[
            _sectionHeader(context, 'KAYITLI HOSTLAR'),
            for (final i in saved) _row(context, i),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text, {Widget? trailing}) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
      child: Row(
        children: [
          Text(
            text,
            style: context.ui(
              size: 11,
              weight: FontWeight.w700,
              color: c.textDim,
              spacing: 0.8,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    final c = context.c;
    final s = suggestions[index];
    final highlighted = index == highlightedIndex;
    final isRecent = s.kind == SuggestionKind.recent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: Key('suggestion-$index'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(s),
        child: Container(
          color: highlighted ? c.accentSoft : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isRecent ? Icons.history : Icons.bookmark_outline,
                size: 15,
                color: c.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(child: _displayText(context, s)),
              if (isRecent)
                Tooltip(
                  message: 'Geçmişten kaldır',
                  child: GestureDetector(
                    key: Key('removeRecent-$index'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onRemoveRecent(s.target),
                    child: Icon(Icons.close, size: 14, color: c.textDim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders [s.display] with the matched substring bolded (ADR 0034 D4). Uses
  /// the mono face for recents (they are `user@host:port`) and the UI face for
  /// saved labels.
  Widget _displayText(BuildContext context, Suggestion s) {
    final c = context.c;
    final base = s.kind == SuggestionKind.recent
        ? context.mono(size: 12.5, color: c.text)
        : context.ui(size: 13, color: c.text);

    if (!s.hasMatch) {
      return Text(s.display, style: base, overflow: TextOverflow.ellipsis);
    }
    final pre = s.display.substring(0, s.matchStart);
    final mid = s.display.substring(s.matchStart, s.matchEnd);
    final post = s.display.substring(s.matchEnd);
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: pre),
          TextSpan(
            text: mid,
            style: base.copyWith(fontWeight: FontWeight.w700, color: c.accent),
          ),
          TextSpan(text: post),
        ],
      ),
    );
  }
}
