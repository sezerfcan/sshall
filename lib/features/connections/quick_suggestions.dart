import '../../data/models/connection.dart';

/// Where a suggestion came from (ADR 0034 D4): a recent target or a saved host.
enum SuggestionKind { recent, saved }

/// One omnibox suggestion (ADR 0034 D4). Pure value object.
class Suggestion {
  final SuggestionKind kind;

  /// Text shown in the row (a recent's `user@host:port`, or a saved label).
  final String display;

  /// The string that is actually connected to when this row is chosen
  /// (the recent target, or a saved host's `[user@]host[:port]`).
  final String target;

  /// Inclusive-exclusive span of the matched substring inside [display], for
  /// bold rendering. Equal start/end (e.g. 0/0) means "no highlight".
  final int matchStart;
  final int matchEnd;

  /// The saved connection backing a [SuggestionKind.saved] row (null for recents).
  final Connection? connection;

  const Suggestion({
    required this.kind,
    required this.display,
    required this.target,
    this.matchStart = 0,
    this.matchEnd = 0,
    this.connection,
  });

  bool get hasMatch => matchEnd > matchStart;
}

/// A scored candidate used internally while ranking.
class _Scored {
  final Suggestion suggestion;
  final int rank; // lower = better
  const _Scored(this.suggestion, this.rank);
}

/// Builds the omnibox suggestion list (ADR 0034 D4). Pure and synchronous.
///
/// Empty [query] → recents first (recency order, as given) then saved hosts,
/// raw. A non-empty [query] fuzzy/substring-matches against each candidate's
/// display text (recents: the target; saved: BOTH label and host) and ranks by
/// match quality (prefix beats interior) with recents ahead of saved on a tie.
/// Duplicate targets are de-duplicated (a recent that is also a saved host
/// appears once, as the recent). Capped at [cap] (~6-8).
List<Suggestion> buildSuggestions({
  required String query,
  required List<String> recents,
  required List<Connection> saved,
  required String Function(Connection) displayOf,
  required String Function(Connection) targetOf,
  required String Function(Connection) hostOf,
  int cap = 8,
}) {
  final q = query.trim().toLowerCase();

  // Track emitted targets so a host present in BOTH recents and saved shows once.
  final seen = <String>{};

  Suggestion recentSug(String target, {int start = 0, int end = 0}) =>
      Suggestion(
        kind: SuggestionKind.recent,
        display: target,
        target: target,
        matchStart: start,
        matchEnd: end,
      );

  Suggestion savedSug(Connection c, {int start = 0, int end = 0}) => Suggestion(
    kind: SuggestionKind.saved,
    display: displayOf(c),
    target: targetOf(c),
    matchStart: start,
    matchEnd: end,
    connection: c,
  );

  if (q.isEmpty) {
    final out = <Suggestion>[];
    for (final t in recents) {
      if (out.length >= cap) break;
      if (seen.add(t)) out.add(recentSug(t));
    }
    for (final c in saved) {
      if (out.length >= cap) break;
      if (seen.add(targetOf(c))) out.add(savedSug(c));
    }
    return out;
  }

  // Match quality: 0 = prefix match, 1 = interior match, absent = no match.
  // recents are emitted before saved at equal quality (kind tiebreak below).
  final scored = <_Scored>[];

  for (final t in recents) {
    final idx = t.toLowerCase().indexOf(q);
    if (idx < 0) continue;
    if (!seen.add(t)) continue;
    final quality = idx == 0 ? 0 : 1;
    scored.add(
      _Scored(recentSug(t, start: idx, end: idx + q.length), quality * 10),
    );
  }

  for (final c in saved) {
    final tgt = targetOf(c);
    final display = displayOf(c).toLowerCase();
    final host = hostOf(c).toLowerCase();
    final dIdx = display.indexOf(q);
    final hIdx = host.indexOf(q);
    if (dIdx < 0 && hIdx < 0) continue;
    if (!seen.add(tgt)) continue;
    // Prefer highlighting the display (label) span; fall back to no span when
    // only the host matched (host isn't shown verbatim in the label).
    final start = dIdx >= 0 ? dIdx : 0;
    final end = dIdx >= 0 ? dIdx + q.length : 0;
    final bestIdx = [
      dIdx,
      hIdx,
    ].where((i) => i >= 0).reduce((a, b) => a < b ? a : b);
    final quality = bestIdx == 0 ? 0 : 1;
    // +1 so a saved row sorts AFTER a recent of the same quality.
    scored.add(_Scored(savedSug(c, start: start, end: end), quality * 10 + 1));
  }

  scored.sort((a, b) => a.rank.compareTo(b.rank));
  final out = [for (final s in scored) s.suggestion];
  return out.length > cap ? out.sublist(0, cap) : out;
}
