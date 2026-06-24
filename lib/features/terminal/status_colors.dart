import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import 'session_status.dart';

/// Pure status → color mapping (ADR 0032 D8). The SAME mapping feeds every
/// surface (tab pill, status bar, host cards, in-pane) so the connection state
/// reads identically everywhere.
///
/// - connected               → green
/// - connecting/authenticating → amber  (NEVER gray for connecting)
/// - error (incl. hostKeyMismatch) → red
/// - disconnected/idle       → textDim (gray)
Color statusColor(SessionState state, ErrorCause? cause, AppColors c) =>
    switch (state) {
      SessionState.connected => c.green,
      SessionState.connecting => c.amber,
      SessionState.authenticating => c.amber,
      SessionState.error => c.red,
      SessionState.disconnected => c.textDim,
    };

/// Convenience overload taking a whole [SessionStatus].
Color statusColorOf(SessionStatus s, AppColors c) =>
    statusColor(s.state, s.cause, c);

/// Whether the status dot should pulse (connecting/authenticating only — D8).
bool statusPulses(SessionState state) =>
    state == SessionState.connecting || state == SessionState.authenticating;
