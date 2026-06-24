import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/features/connect/widgets/host_paste_parser.dart';
import 'package:sshall/features/connections/quick_connect_router.dart';

/// Unit coverage for the pure parser-router (ADR 0034 D2): saved-host matching
/// (host / host:port / label), case/trim tolerance, host:port priority, and the
/// ephemeral/fallback routing decision. No UI, no store.
Connection _conn(
  String id,
  String label,
  String host, {
  int? port,
  String? authRef,
}) => Connection(
  id: id,
  label: label,
  host: host,
  folderId: null,
  username: 'root',
  port: port,
  authRef: authRef,
  tags: const [],
  order: 0,
);

void main() {
  String? hostOf(Connection c) => c.host;
  int portOf(Connection c) => c.port ?? 22;
  String labelOf(Connection c) => c.label;
  bool connectable(Connection c) => c.authRef != null;

  Connection? match(String raw, List<Connection> conns) => matchSavedHost(
    parseHostPaste(raw),
    conns,
    resolvedHost: hostOf,
    resolvedPort: portOf,
    labelOf: labelOf,
  );

  group('matchSavedHost', () {
    final web = _conn('web', 'Prod Web', 'web.example.com', port: 22);
    final db = _conn('db', 'db-1', 'db.internal', port: 2222);
    final all = [web, db];

    test('user@host:port matches a saved host:port', () {
      expect(match('root@db.internal:2222', all), db);
    });

    test('bare host matches a saved host (port-agnostic)', () {
      expect(match('web.example.com', all), web);
    });

    test('label matches a saved host', () {
      expect(match('db-1', all), db);
    });

    test('no match returns null', () {
      expect(match('nope.example.com', all), isNull);
    });

    test('case + trim tolerant (HOST == host)', () {
      expect(match('  WEB.EXAMPLE.COM ', all), web);
    });

    test('host:port priority: exact-port record wins over port-less', () {
      final p22 = _conn('p22', 'srv', 'srv.com', port: 22);
      final p2222 = _conn('p2222', 'srv-alt', 'srv.com', port: 2222);
      // Both share a host; the parsed :2222 must select the 2222 record.
      expect(match('srv.com:2222', [p22, p2222]), p2222);
    });
  });

  group('route', () {
    final saved = _conn('web', 'web', 'web.example.com', authRef: 'i1');
    final danglingCred = _conn('bad', 'bad', 'bad.com'); // authRef null

    QuickRouteDecision decide(String raw, List<Connection> conns) => route(
      parseHostPaste(raw),
      conns,
      resolvedHost: hostOf,
      resolvedPort: portOf,
      labelOf: labelOf,
      isConnectable: connectable,
    );

    test(
      'matched + connectable saved host → ephemeralSaved with Connection',
      () {
        final d = decide('web.example.com', [saved]);
        expect(d.route, QuickRoute.ephemeralSaved);
        expect(d.connection, saved);
      },
    );

    test('no match → fallbackDialog', () {
      final d = decide('new.example.com', [saved]);
      expect(d.route, QuickRoute.fallbackDialog);
      expect(d.connection, isNull);
    });

    test('host null (empty input) → fallbackDialog', () {
      final d = decide('   ', [saved]);
      expect(d.route, QuickRoute.fallbackDialog);
    });

    test(
      'matched but NOT connectable → fallbackDialog (user supplies auth)',
      () {
        final d = decide('bad.com', [danglingCred]);
        expect(d.route, QuickRoute.fallbackDialog);
        expect(d.connection, isNull);
      },
    );
  });
}
