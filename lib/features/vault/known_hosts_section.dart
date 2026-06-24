import 'package:flutter/material.dart';

import '../../data/models/host_key_pin.dart';
import '../../theme/context_ext.dart';
import '../../widgets/section_label.dart';
import '../../widgets/tag.dart';
import 'vault_format.dart';

/// "Bilinen Hostlar" section (ADR 0033 / D5): lists the pinned host keys
/// (VaultData.pins), filterable by host, each with a per-row REVOKE. The pin's
/// SHA256 is non-secret; it is shown truncated with the full value on tooltip.
class KnownHostsSection extends StatelessWidget {
  final List<HostKeyPin> pins;

  /// Host substring filter (case-insensitive).
  final String query;
  final ValueChanged<HostKeyPin> onRevoke;

  const KnownHostsSection({
    super.key,
    required this.pins,
    required this.query,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? pins
        : [
            for (final p in pins)
              if (p.hostPort.toLowerCase().contains(q)) p,
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SectionLabel('Bilinen Hostlar'),
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Daha önce güvendiğin sunucu anahtarları (TOFU). Sunucunun '
                  'anahtarı değişirse uyarı alırsın.',
              child: Icon(Icons.help_outline, size: 13, color: c.textDim),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (pins.isEmpty)
          _empty(context, 'Henüz sabitlenmiş host anahtarı yok')
        else if (filtered.isEmpty)
          _empty(context, 'Aramayla eşleşen host yok')
        else
          for (final pin in filtered) ...[
            _PinRow(pin: pin, onRevoke: () => onRevoke(pin)),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _empty(BuildContext context, String text) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.border),
      ),
      child: Center(
        child: Text(text, style: context.ui(size: 12.5, color: c.textDim)),
      ),
    );
  }
}

class _PinRow extends StatelessWidget {
  final HostKeyPin pin;
  final VoidCallback onRevoke;
  const _PinRow({required this.pin, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Pins store the raw base64 (no "SHA256:" label); add it for display so it
    // reads like an OpenSSH fingerprint and matches identity fingerprints.
    final full = 'SHA256:${pin.sha256}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, size: 16, color: c.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pin.hostPort,
              style: context.ui(size: 13, weight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Tag(text: pin.keyType),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Sunucu anahtarının SHA256 parmak izi\n$full',
            child: Text(
              shortFingerprint(full),
              style: context.mono(size: 11, color: c.textDim),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message:
                'Bu pini unut: sonraki bağlantıda sunucu yeniden güven sorar (TOFU)',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRevoke,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'İptal et',
                    style: context.ui(
                      size: 12,
                      weight: FontWeight.w600,
                      color: c.red,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
