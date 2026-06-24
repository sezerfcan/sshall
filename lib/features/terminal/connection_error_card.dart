import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import 'session_status.dart';

/// Persistent, actionable in-pane error surface (ADR 0032 D3/D4) — replaces the
/// transient connect SnackBars and the raw red terminal line.
///
/// Two variants, driven by [status]:
/// - [SessionState.error] → a cause-mapped Turkish title + one-line remedy +
///   an expandable "Detaylar" disclosure (raw message, monospace) + actions
///   `[Yeniden Dene]` (reconnect) and `[Bağlantıyı Düzenle]` (edit).
/// - unexpected [SessionState.disconnected] (`userInitiated == false`) → a
///   "Bağlantı kesildi" card + `[Yeniden Bağlan]`.
///
/// `hostKeyMismatch` uses warning weight (amber frame, no primary "trust"
/// action) so the possible-MITM case never gets misleading success styling.
class ConnectionErrorCard extends StatefulWidget {
  final SessionStatus status;

  /// The human `host:port` (shown as context; '' = endpoint-less).
  final String hostPort;

  /// Reconnect — re-runs connect on the same tab/controller (D5).
  final VoidCallback onRetry;

  /// Open the edit dialog for this connection (D3). Null hides the edit action
  /// (e.g. Docker exec sessions with no editable connection).
  final VoidCallback? onEdit;

  const ConnectionErrorCard({
    super.key,
    required this.status,
    required this.hostPort,
    required this.onRetry,
    this.onEdit,
  });

  @override
  State<ConnectionErrorCard> createState() => _ConnectionErrorCardState();
}

class _ConnectionErrorCardState extends State<ConnectionErrorCard> {
  bool _expanded = false;

  bool get _isDisconnect =>
      widget.status.state == SessionState.disconnected &&
      !widget.status.userInitiated;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final status = widget.status;

    // Resolve title / hint / severity from the cause (or the disconnect variant).
    final String title;
    final String hint;
    final bool warning;
    final String retryLabel;
    if (_isDisconnect) {
      title = 'Bağlantı kesildi';
      hint = 'Sunucuyla bağlantı beklenmedik şekilde sona erdi';
      warning = false;
      retryLabel = 'Yeniden Bağlan';
    } else {
      final copy = causeCopy(status.cause ?? ErrorCause.unknown);
      title = copy.title;
      hint = copy.hint;
      warning = copy.warning;
      retryLabel = 'Yeniden Dene';
    }

    // Warning (host-key mismatch) frames amber; a plain error frames red.
    final accent = warning ? c.amber : c.red;
    final raw = status.rawMessage;

    return ColoredBox(
      color: c.termBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: .55)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      warning ? Icons.gpp_maybe_outlined : Icons.error_outline,
                      size: 22,
                      color: accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: context.ui(
                              size: 15,
                              weight: FontWeight.w700,
                              color: c.text,
                            ),
                          ),
                          if (widget.hostPort.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.hostPort,
                              style: context.mono(size: 11.5, color: c.textDim),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // One-line remedy hint (human UI text).
                Text(hint, style: context.ui(size: 12.5, color: c.textMuted)),

                // "Detaylar" disclosure: the raw library/server message, mono.
                if (raw != null && raw.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DetailsDisclosure(
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                    raw: raw,
                  ),
                ],

                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Tooltip(
                      message: _isDisconnect
                          ? 'Aynı sekmede yeniden bağlan'
                          : 'Bağlantıyı yeniden dene',
                      child: PrimaryButton(
                        key: const Key('errorRetry'),
                        label: retryLabel,
                        icon: Icons.refresh,
                        onPressed: widget.onRetry,
                      ),
                    ),
                    if (widget.onEdit != null)
                      Tooltip(
                        message: 'Bu bağlantının ayarlarını düzenle',
                        child: SecondaryButton(
                          key: const Key('errorEdit'),
                          label: 'Bağlantıyı Düzenle',
                          onPressed: widget.onEdit,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsible "Detaylar" block holding the raw message (mono).
class _DetailsDisclosure extends StatelessWidget {
  const _DetailsDisclosure({
    required this.expanded,
    required this.onToggle,
    required this.raw,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final String raw;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Ham hata mesajını göster/gizle',
          child: GestureDetector(
            key: const Key('errorDetailsToggle'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: c.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Detaylar',
                  style: context.ui(
                    size: 12,
                    weight: FontWeight.w600,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: SelectableText(
              raw,
              key: const Key('errorRawMessage'),
              style: context.mono(size: 11.5, color: c.textMuted),
            ),
          ),
        ],
      ],
    );
  }
}
