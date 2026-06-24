import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import 'session_status.dart';
import 'status_colors.dart';

/// The thin status strip below a terminal pane (ADR 0032 D7): a color-mapped
/// status dot + localized Turkish label, the real `host:port`, the negotiated
/// cipher (when known), a clickable [Yeniden bağlan] affordance when not
/// connected, and the zoom controls on the right.
class TerminalStatusBar extends StatelessWidget {
  /// The rich session status (single source of truth, ADR 0032 D1).
  final SessionStatus status;

  /// Real `host:port` for this session ('' for endpoint-less sessions).
  final String hostPort;

  /// Negotiated cipher once connected; null hides the cipher cell.
  final String? cipher;

  final double fontSize;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  /// Manual reconnect (D5/D7). When non-null and the session is not connected,
  /// the dot/label become a clickable "Yeniden bağlan" affordance.
  final VoidCallback? onReconnect;

  const TerminalStatusBar({
    super.key,
    required this.status,
    required this.hostPort,
    required this.fontSize,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    this.cipher,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dotColor = statusColorOf(status, c);
    // Offer reconnect when not connected and a handler is wired (error/drop).
    final showReconnect = onReconnect != null && !status.isConnected;

    Widget dot(Color col) => Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
    );
    Widget sep() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('·', style: context.mono(size: 11, color: c.textDim)),
    );
    Widget zoomBtn(String key, IconData icon, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: GestureDetector(
            key: Key(key),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: 24,
              height: 24,
              child: Center(child: Icon(icon, size: 13, color: c.textMuted)),
            ),
          ),
        );

    // The dot + localized label. Clickable (reconnect) when not connected.
    final statusCluster = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(dotColor),
        const SizedBox(width: 6),
        Text(
          statusLabel(status),
          style: context.ui(size: 11, color: c.textMuted),
        ),
        if (showReconnect) ...[
          const SizedBox(width: 8),
          Icon(Icons.refresh, size: 12, color: c.accent),
          const SizedBox(width: 3),
          Text(
            'Yeniden bağlan',
            style: context.ui(
              size: 11,
              weight: FontWeight.w600,
              color: c.accent,
            ),
          ),
        ],
      ],
    );

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (showReconnect)
            Tooltip(
              message: 'Yeniden bağlan',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: const Key('statusReconnect'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onReconnect,
                  child: statusCluster,
                ),
              ),
            )
          else
            statusCluster,
          if (hostPort.isNotEmpty) ...[
            sep(),
            // Flexible + ellipsis so a long host:port (or a narrow pane) never
            // overflows the strip — it truncates instead.
            Flexible(
              child: Text(
                hostPort,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mono(size: 11, color: c.textMuted),
              ),
            ),
          ],
          if (cipher != null) ...[
            sep(),
            Icon(Icons.lock_outline, size: 11, color: c.green),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                cipher!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mono(size: 11, color: c.textMuted),
              ),
            ),
          ],
          const Spacer(),
          zoomBtn(
            'zoomOut',
            Icons.remove,
            'Yazıyı küçült (Cmd/Ctrl -)',
            onZoomOut,
          ),
          Tooltip(
            message: 'Yazı boyutunu sıfırla (Cmd/Ctrl 0)',
            child: GestureDetector(
              key: const Key('zoomReset'),
              behavior: HitTestBehavior.opaque,
              onTap: onZoomReset,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${fontSize.toStringAsFixed(0)}pt',
                  style: context.mono(size: 11, color: c.textMuted),
                ),
              ),
            ),
          ),
          zoomBtn('zoomIn', Icons.add, 'Yazıyı büyüt (Cmd/Ctrl +)', onZoomIn),
        ],
      ),
    );
  }
}
