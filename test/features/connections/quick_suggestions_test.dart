import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/features/connections/quick_suggestions.dart';

/// Unit coverage for the pure omnibox ranking (ADR 0034 D4): empty-query raw
/// list, substring match on host + label, prefix-before-interior ranking,
/// recent-before-saved tie-break, match span, and dedup across recents/saved.
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
  String displayOf(Connection c) => c.label;
  String targetOf(Connection c) => 'root@${c.host}:22';
  String hostOf(Connection c) => c.host;

  List<Suggestion> build(
    String query, {
    List<String> recents = const [],
    List<Connection> saved = const [],
    int cap = 8,
  }) => buildSuggestions(
    query: query,
    recents: recents,
    saved: saved,
    displayOf: displayOf,
    targetOf: targetOf,
    hostOf: hostOf,
    cap: cap,
  );

  test('empty query → recents (recency-first) then saved; cap respected', () {
    final out = build(
      '',
      recents: ['root@a.com:22', 'root@b.com:22'],
      saved: [_conn('1', 'web', 'web.com')],
    );
    expect(out.map((s) => s.display).toList(), [
      'root@a.com:22',
      'root@b.com:22',
      'web',
    ]);
    expect(out[0].kind, SuggestionKind.recent);
    expect(out[2].kind, SuggestionKind.saved);

    final capped = build(
      '',
      recents: List.generate(20, (i) => 'root@h$i.com:22'),
      cap: 8,
    );
    expect(capped.length, 8);
  });

  test('query matches host substring and label substring; misses excluded', () {
    final saved = [
      _conn('1', 'Prod Web', 'web.example.com'),
      _conn('2', 'Database', 'db.internal'),
    ];
    // Matches by host substring.
    final byHost = build('example', saved: saved);
    expect(byHost.map((s) => s.display), contains('Prod Web'));
    expect(byHost.map((s) => s.display), isNot(contains('Database')));

    // Matches by label substring.
    final byLabel = build('data', saved: saved);
    expect(byLabel.map((s) => s.display), contains('Database'));
  });

  test('ranking: prefix beats interior; recent beats saved at equal quality', () {
    final saved = [_conn('1', 'prod', 'prod.com')];
    // recent "prod@x" prefix-matches 'prod'; saved 'prod' label prefix-matches.
    final out = build('prod', recents: ['prod@x.com:22'], saved: saved);
    // Both are prefix (quality 0); the recent must come first.
    expect(out.first.kind, SuggestionKind.recent);

    // Interior match ranks after a prefix match.
    final saved2 = [
      _conn('1', 'my-prod', 'a.com'), // interior 'prod'
      _conn('2', 'prod-x', 'b.com'), // prefix 'prod'
    ];
    final ranked = build('prod', saved: saved2);
    expect(ranked.first.display, 'prod-x'); // prefix first
    expect(ranked.last.display, 'my-prod'); // interior last
  });

  test('match span marks the matched substring for bold rendering', () {
    final out = build('web', saved: [_conn('1', 'my-web-1', 'h.com')]);
    final s = out.single;
    expect(s.display.substring(s.matchStart, s.matchEnd), 'web');
    expect(s.hasMatch, isTrue);
  });

  test('same target in recents and saved → single row (dedup), cap kept', () {
    final saved = [_conn('1', 'web', 'web.com')];
    final out = build(
      '',
      recents: ['root@web.com:22'], // identical to targetOf(saved[0])
      saved: saved,
    );
    expect(out.length, 1);
    expect(out.single.kind, SuggestionKind.recent);
  });
}
