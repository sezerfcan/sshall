import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import 'session_status.dart';
import 'status_colors.dart';

/// Centered in-pane "connecting…" surface shown while a terminal tab is opened
/// immediately on connect (ADR 0032 D2). It advances its phase text with the
/// [status] (connecting → "host:port adresine bağlanılıyor…", authenticating →
/// "Kimlik doğrulanıyor…") and offers an [İptal] (cancel = close the session/
/// tab). The host-key dialog still appears over this pane during connect; this
/// surface never blocks it.
class ConnectingPane extends StatefulWidget {
  final SessionStatus status;

  /// The human `host:port` shown in the connecting phrase ('' = endpoint-less).
  final String hostPort;

  /// Cancel the connect — closes the session/tab (D2).
  final VoidCallback onCancel;

  const ConnectingPane({
    super.key,
    required this.status,
    required this.hostPort,
    required this.onCancel,
  });

  @override
  State<ConnectingPane> createState() => _ConnectingPaneState();
}

class _ConnectingPaneState extends State<ConnectingPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String get _phrase {
    if (widget.status.state == SessionState.authenticating) {
      return 'Kimlik doğrulanıyor…';
    }
    return widget.hostPort.isEmpty
        ? 'Bağlanılıyor…'
        : '${widget.hostPort} adresine bağlanılıyor…';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final amber = statusColorOf(widget.status, c);
    return ColoredBox(
      color: c.termBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Amber, pulsing progress indicator (never gray for connecting, D8).
            FadeTransition(
              opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_pulse),
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(amber),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _phrase,
              key: const Key('connectingPhrase'),
              textAlign: TextAlign.center,
              style: context.ui(size: 13.5, color: c.textMuted),
            ),
            const SizedBox(height: 20),
            Tooltip(
              message: 'Bağlanmayı iptal et ve sekmeyi kapat',
              child: GhostButton(
                key: const Key('connectingCancel'),
                label: 'İptal',
                onPressed: widget.onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
