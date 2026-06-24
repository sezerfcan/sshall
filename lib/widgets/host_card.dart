import 'package:flutter/material.dart';
import '../features/terminal/session_status.dart';
import '../features/terminal/status_colors.dart';
import '../theme/context_ext.dart';

class HostCard extends StatelessWidget {
  final String name, addr;
  final bool connected, selected;
  final List<Widget> tags;
  final String? trailingText;
  final VoidCallback? onTap;
  final IconData icon;

  /// Live session status for this host (ADR 0032 D6). When non-null it drives
  /// the status dot color (green/amber/red/dim); when null the legacy
  /// [connected] bool decides (green/dim).
  final SessionStatus? status;

  const HostCard({
    super.key,
    required this.name,
    required this.addr,
    required this.connected,
    this.tags = const [],
    this.trailingText,
    this.onTap,
    this.selected = false,
    this.icon = Icons.dns_outlined,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Live status drives the dot when available; otherwise the legacy flag.
    final dotColor = status != null
        ? statusColorOf(status!, c)
        : (connected ? c.green : c.textDim);
    final dotTip = status != null
        ? statusLabel(status!)
        : (connected ? 'Bağlı' : 'Bağlı değil');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 17, color: c.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.ui(size: 14, weight: FontWeight.w600),
                        ),
                        Text(
                          addr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.mono(size: 11.5, color: c.textDim),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: dotTip,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              if (tags.isNotEmpty || trailingText != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    ...tags.expand((t) => [t, const SizedBox(width: 6)]),
                    const Spacer(),
                    if (trailingText != null)
                      Text(
                        trailingText!,
                        style: context.ui(size: 10.5, color: c.textDim),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
