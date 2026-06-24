import '../../data/models/connection.dart';
import '../connect/widgets/host_paste_parser.dart';

/// Where a parsed Quick Connect target should be routed (ADR 0034 D2).
enum QuickRoute {
  /// The target matched a SAVED host with a resolvable identity → connect
  /// EPHEMERALLY, reusing its stored credential, writing NO new vault entry.
  ephemeralSaved,

  /// New host / no resolvable credential → open the prefilled full dialog as a
  /// fallback (the user picks auth there; saving is opt-in via that dialog).
  fallbackDialog,
}

/// The outcome of routing a parsed target. For [QuickRoute.ephemeralSaved] the
/// matched [connection] is set; for [QuickRoute.fallbackDialog] it is null.
class QuickRouteDecision {
  final QuickRoute route;
  final Connection? connection;
  const QuickRouteDecision(this.route, [this.connection]);
}

/// Finds the saved [Connection] a parsed target refers to (ADR 0034 D2),
/// matching by host / host:port / label. Pure and synchronous.
///
/// [resolvedHost] yields a connection's effective host (so callers can inject
/// folder-resolved values without this layer touching the store); [labelOf]
/// yields its label. Matching is case-insensitive and trims whitespace.
///
/// Priority when several connections match (most specific first):
///   1. exact host:port  2. host (no port required)  3. label.
/// Returns null when [t] has no host or nothing matches.
Connection? matchSavedHost(
  ParsedTarget t,
  List<Connection> conns, {
  required String? Function(Connection) resolvedHost,
  required int Function(Connection) resolvedPort,
  required String Function(Connection) labelOf,
}) {
  final host = t.host?.trim().toLowerCase();
  if (host == null || host.isEmpty) return null;

  Connection? hostOnly;
  Connection? labelMatch;

  for (final c in conns) {
    final ch = resolvedHost(c)?.trim().toLowerCase();
    final cl = labelOf(c).trim().toLowerCase();

    if (ch != null && ch == host) {
      // Exact host:port wins immediately when the target carried a port.
      if (t.port != null && resolvedPort(c) == t.port) return c;
      hostOnly ??= c;
    }
    if (cl == host) {
      labelMatch ??= c;
    }
  }

  // host (port-agnostic) beats a label match.
  return hostOnly ?? labelMatch;
}

/// Decides how to route a parsed target (ADR 0034 D2). Pure: the caller still
/// resolves credentials and performs the actual connect/dialog. A match exists
/// AND is connectable (a resolvable identity) → [QuickRoute.ephemeralSaved];
/// otherwise → [QuickRoute.fallbackDialog].
///
/// [isConnectable] lets the caller inject the `paramsFor() != null` check so the
/// router need not know about identities/folders. A matched-but-unconnectable
/// host (dangling credential) still falls back to the dialog so the user can
/// supply auth there.
QuickRouteDecision route(
  ParsedTarget t,
  List<Connection> conns, {
  required String? Function(Connection) resolvedHost,
  required int Function(Connection) resolvedPort,
  required String Function(Connection) labelOf,
  required bool Function(Connection) isConnectable,
}) {
  final match = matchSavedHost(
    t,
    conns,
    resolvedHost: resolvedHost,
    resolvedPort: resolvedPort,
    labelOf: labelOf,
  );
  if (match != null && isConnectable(match)) {
    return QuickRouteDecision(QuickRoute.ephemeralSaved, match);
  }
  return const QuickRouteDecision(QuickRoute.fallbackDialog);
}
