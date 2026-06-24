/// Pure parser that splits a pasted connection target into username/host/port
/// (ADR 0031, D7). Reused by the connect dialog's Host field (auto-split on
/// paste) and unit-tested in isolation.
///
/// Accepts forms like:
///   host
///   user@host
///   user@host:2222
///   ssh user@host -p 2222
///   [2001:db8::1]            (bracketed IPv6)
///   user@[2001:db8::1]:2222  (bracketed IPv6 with user + port)
library;

/// The result of parsing a pasted target. Any field may be null when the input
/// did not carry it, so the caller can fill ONLY the fields it found and leave
/// the rest untouched.
class ParsedTarget {
  final String? username;
  final String? host;
  final int? port;

  const ParsedTarget({this.username, this.host, this.port});

  /// True when the input carried more than a bare host — i.e. parsing actually
  /// split something out (a user, a port, or an `ssh ` prefix). The dialog uses
  /// this to decide whether a paste is "structured" enough to fan out into the
  /// separate fields instead of dumping the whole string into Host.
  bool get isStructured => username != null || port != null;
}

/// Parses [raw] into a [ParsedTarget]. Pure and synchronous.
ParsedTarget parseHostPaste(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return const ParsedTarget();

  int? port;

  // `ssh ... -p N` / `-pN` flag anywhere in the string.
  final pMatch = RegExp(r'-p\s*(\d+)').firstMatch(s);
  if (pMatch != null) {
    port = int.tryParse(pMatch.group(1)!);
    s = s.replaceFirst(pMatch.group(0)!, ' ').trim();
  }

  // Strip a leading `ssh ` so `ssh user@host` parses like `user@host`.
  s = s.replaceFirst(RegExp(r'^ssh\s+'), '').trim();

  // After removing the flag, an `ssh` line can still carry trailing tokens
  // (extra options); keep only the first whitespace-separated token, which is
  // the [user@]host[:port] destination.
  if (s.contains(RegExp(r'\s'))) {
    s = s
        .split(RegExp(r'\s+'))
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  }

  // Split off an optional `user@` prefix. Use the LAST '@' so a username
  // containing '@' is unusual but a host never is; SSH itself uses the last.
  String? user;
  final at = s.lastIndexOf('@');
  if (at >= 0) {
    user = s.substring(0, at);
    s = s.substring(at + 1);
    if (user.isEmpty) user = null;
  }

  // Bracketed IPv6: `[::1]` or `[::1]:2222`. The brackets disambiguate the
  // address colons from a trailing port colon.
  String host;
  final bracket = RegExp(r'^\[([^\]]+)\](?::(\d+))?$').firstMatch(s);
  if (bracket != null) {
    host = bracket.group(1)!;
    port ??= int.tryParse(bracket.group(2) ?? '');
  } else {
    // Unbracketed. A single trailing `:port` is a port ONLY when the rest has
    // no other colon (otherwise it is a bare IPv6 literal like `2001:db8::1`).
    final lastColon = s.lastIndexOf(':');
    if (lastColon > 0 && s.indexOf(':') == lastColon) {
      final maybePort = int.tryParse(s.substring(lastColon + 1));
      if (maybePort != null) {
        port ??= maybePort;
        s = s.substring(0, lastColon);
      }
    }
    host = s;
  }

  return ParsedTarget(
    username: user,
    host: host.isEmpty ? null : host,
    port: port,
  );
}
