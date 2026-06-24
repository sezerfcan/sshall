/// First-class, observable connection lifecycle for a single terminal session
/// (ADR 0032 D1/D4). The isolate protocol (`SshStatus`, `ErrorEvent.code`,
/// `ClosedEvent`) is UNCHANGED; the controller translates those worker events
/// into this richer value object, which is the single source of truth every
/// surface (status bar, error card, host cards, in-pane) reads from.
///
/// Pure data + a pure classifier + a pure Turkish copy map — no UI, no I/O — so
/// it is trivially unit-testable.
library;

/// The lifecycle state of a session.
///
/// `reconnecting` is RESERVED for pass-2 (auto-reconnect + backoff + attempt
/// counter, ADR 0032 scope-out) and is intentionally NOT part of this enum yet.
enum SessionState {
  /// Socket connect in flight ("host:port adresine bağlanılıyor…").
  connecting,

  /// Authenticating after the socket is up ("Kimlik doğrulanıyor…").
  authenticating,

  /// Live shell/exec channel ready.
  connected,

  /// A connect/auth/host-key/network failure surfaced (see [SessionStatus.cause]).
  error,

  /// The session ended. [SessionStatus.userInitiated] separates a user-driven
  /// close (no reconnect offered) from an unexpected drop (reconnect offered).
  disconnected,
}

/// The mapped reason a session failed (ADR 0032 D4). Derived purely from the
/// worker's `ErrorEvent.code` + message by [classifyError].
enum ErrorCause {
  /// Wrong username/password/key, or a key that could not be imported.
  auth,

  /// TCP connection actively refused (port closed / nothing listening).
  refused,

  /// Host name could not be resolved (DNS).
  dns,

  /// Connect/handshake timed out.
  timeout,

  /// The presented host key did NOT match the pinned one — possible MITM.
  hostKeyMismatch,

  /// Anything else; the raw message is kept in [SessionStatus.rawMessage].
  unknown,
}

/// Immutable snapshot of a session's lifecycle. Single source of truth (D1).
class SessionStatus {
  final SessionState state;

  /// Set only when [state] is [SessionState.error].
  final ErrorCause? cause;

  /// The raw library/server message. ALWAYS preserved on error so the error
  /// card's "Detaylar" disclosure can show it verbatim (D4).
  final String? rawMessage;

  /// For [SessionState.disconnected]: true when the user closed the tab/session
  /// (no reconnect offered), false on an unexpected drop (reconnect offered) —
  /// ADR 0032 D1/D5. Meaningless for other states (kept false).
  final bool userInitiated;

  const SessionStatus({
    required this.state,
    this.cause,
    this.rawMessage,
    this.userInitiated = false,
  });

  const SessionStatus.connecting() : this(state: SessionState.connecting);
  const SessionStatus.authenticating()
    : this(state: SessionState.authenticating);
  const SessionStatus.connected() : this(state: SessionState.connected);

  /// An unexpected drop (server kill / network loss) — reconnect is offered.
  const SessionStatus.dropped()
    : this(state: SessionState.disconnected, userInitiated: false);

  /// A user-initiated close — no reconnect is offered.
  const SessionStatus.closedByUser()
    : this(state: SessionState.disconnected, userInitiated: true);

  bool get isError => state == SessionState.error;
  bool get isConnected => state == SessionState.connected;
  bool get isConnecting =>
      state == SessionState.connecting || state == SessionState.authenticating;

  /// Whether a reconnect affordance should be offered: on any error, or on an
  /// unexpected (non-user) disconnect (D3/D5).
  bool get canReconnect =>
      isError || (state == SessionState.disconnected && !userInitiated);

  @override
  bool operator ==(Object other) =>
      other is SessionStatus &&
      other.state == state &&
      other.cause == cause &&
      other.rawMessage == rawMessage &&
      other.userInitiated == userInitiated;

  @override
  int get hashCode => Object.hash(state, cause, rawMessage, userInitiated);

  @override
  String toString() =>
      'SessionStatus(${state.name}, cause: $cause, userInitiated: $userInitiated)';
}

/// Pure classifier: maps a worker `ErrorEvent(code, message)` to a
/// [SessionStatus] in [SessionState.error] with the mapped [ErrorCause]. The
/// raw [message] is ALWAYS preserved in [SessionStatus.rawMessage] (D4).
///
/// - `auth`    → [ErrorCause.auth]
/// - `hostkey` → [ErrorCause.hostKeyMismatch]
/// - `network` → sub-classified from [message]: dns / refused / timeout, else
///   [ErrorCause.unknown] (the code stays network; only the mapped cause is
///   unknown when the message is unrecognised).
/// - anything else → [ErrorCause.unknown]
SessionStatus classifyError(String code, String message) {
  final cause = switch (code) {
    'auth' => ErrorCause.auth,
    'hostkey' => ErrorCause.hostKeyMismatch,
    'network' => _networkCause(message),
    _ => ErrorCause.unknown,
  };
  return SessionStatus(
    state: SessionState.error,
    cause: cause,
    rawMessage: message,
  );
}

/// Sub-classifies a `network` error from its message. Matching is
/// case-insensitive and substring-based so it tolerates the varied phrasings
/// dart:io / dartssh2 emit across platforms.
ErrorCause _networkCause(String message) {
  final m = message.toLowerCase();
  // DNS resolution failures.
  if (m.contains('failed host lookup') ||
      m.contains('could not resolve') ||
      m.contains('name or service not known') ||
      m.contains('nodename nor servname') ||
      m.contains('no address associated') ||
      m.contains('name resolution')) {
    return ErrorCause.dns;
  }
  // Actively refused (port closed).
  if (m.contains('connection refused') ||
      m.contains('errno = 61') ||
      m.contains('errno = 111')) {
    return ErrorCause.refused;
  }
  // Timeouts.
  if (m.contains('timed out') ||
      m.contains('timeout') ||
      m.contains('connection timed out')) {
    return ErrorCause.timeout;
  }
  return ErrorCause.unknown;
}

/// Turkish, cause-mapped copy for the error surface (D4). [title] is a short
/// human label, [hint] a one-line remedy, [warning] true only for the
/// possible-MITM host-key mismatch so the surface can use warning weight
/// instead of a plain error.
typedef CauseCopy = ({String title, String hint, bool warning});

CauseCopy causeCopy(ErrorCause cause) => switch (cause) {
  ErrorCause.auth => (
    title: 'Kimlik doğrulama başarısız',
    hint: 'Kullanıcı adı, şifre veya anahtarı kontrol edin',
    warning: false,
  ),
  ErrorCause.hostKeyMismatch => (
    title: 'Ana makine anahtarı DEĞİŞTİ',
    hint: 'Sunucu kimliği beklenenle uyuşmuyor — MITM olabilir',
    warning: true,
  ),
  ErrorCause.dns => (
    title: 'Ana makine bulunamadı (DNS)',
    hint: 'Adresi kontrol edin; ağ/DNS erişiminizi doğrulayın',
    warning: false,
  ),
  ErrorCause.refused => (
    title: 'Bağlantı reddedildi',
    hint: 'Sunucu çalışıyor mu, port doğru mu kontrol edin',
    warning: false,
  ),
  ErrorCause.timeout => (
    title: 'Zaman aşımı',
    hint: 'Sunucuya ulaşılamadı; ağ veya güvenlik duvarını kontrol edin',
    warning: false,
  ),
  ErrorCause.unknown => (
    title: 'Bağlantı hatası',
    hint: 'Ayrıntılar için aşağıyı genişletin',
    warning: false,
  ),
};

/// Turkish, localized status label for a [SessionStatus] (D7). Used by the
/// status bar and tooltips — no raw English tokens reach the UI.
String statusLabel(SessionStatus status) => switch (status.state) {
  SessionState.connecting => 'Bağlanılıyor…',
  SessionState.authenticating => 'Kimlik doğrulanıyor…',
  SessionState.connected => 'Bağlı',
  SessionState.error => 'Hata',
  SessionState.disconnected =>
    status.userInitiated ? 'Kapatıldı' : 'Bağlantı kesildi',
};
