import 'package:flutter/material.dart';

import '../../data/models/connection.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_label.dart';
import '../../widgets/tag.dart';
import 'identity_view_model.dart';
import 'vault_format.dart';

/// Identity detail surface (ADR 0033 / D3). Shown as a dialog on narrow windows
/// or a right pane on wide ones. Surfaces ONLY non-secret material: label,
/// algorithm, creation date, full SHA256 fingerprint, the "using" connections,
/// and the one-line public key. The private key / passphrase are NEVER
/// rendered (ADR 0005).
class IdentityDetail extends StatelessWidget {
  final IdentityView view;
  final int usage;

  /// Connections that reference this identity (for "Kullanan bağlantılar").
  final List<Connection> referencingConnections;

  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onExport;
  final VoidCallback? onCopyPublicKey;
  final VoidCallback? onCopyFingerprint;
  final ValueChanged<Connection>? onJumpToConnection;

  const IdentityDetail({
    super.key,
    required this.view,
    required this.usage,
    required this.referencingConnections,
    required this.onRename,
    required this.onDelete,
    this.onExport,
    this.onCopyPublicKey,
    this.onCopyFingerprint,
    this.onJumpToConnection,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = view.identity;
    final fp = view.fingerprint;
    final publicKey = view.publicKeyOpenSSH;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header: label + algorithm tag + rename ──────────────────────────
        Row(
          children: [
            Icon(
              view.isKey ? Icons.vpn_key_outlined : Icons.password_outlined,
              size: 18,
              color: c.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                id.label,
                style: context.ui(size: 17, weight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Tag(text: view.algorithmLabel),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Etiketi yeniden adlandır',
              child: AppIconButton(
                key: const Key('detailRename'),
                icon: Icons.edit_outlined,
                size: 32,
                onPressed: onRename,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── Metadata block ──────────────────────────────────────────────────
        const SectionLabel('Bilgi'),
        const SizedBox(height: 10),
        _MetaRow(label: 'Tür', value: view.isKey ? 'SSH anahtarı' : 'Parola'),
        _MetaRow(label: 'Algoritma', value: view.algorithmLabel),
        _MetaRow(label: 'Oluşturulma', value: formatCreatedAt(id.createdAt)),
        _MetaRow(
          label: 'Kullanım',
          value: usage > 0 ? '$usage bağlantı' : 'Kullanılmıyor',
        ),

        // ── Fingerprint ─────────────────────────────────────────────────────
        if (fp != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SectionLabel('SHA256 parmak izi'),
              const SizedBox(width: 6),
              Tooltip(
                message:
                    'Sunucunun bildirdiği anahtarın parmak iziyle karşılaştırarak '
                    'doğru anahtarı kullandığını doğrularsın.',
                child: Icon(Icons.help_outline, size: 13, color: c.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CopyableBox(
            key: const Key('detailFingerprint'),
            text: fp,
            onCopy: onCopyFingerprint,
            copyTooltip: 'Parmak izini kopyala',
          ),
        ],

        // ── Public key box ──────────────────────────────────────────────────
        if (publicKey != null) ...[
          const SizedBox(height: 16),
          const SectionLabel('Genel anahtar (sunucuya ekle)'),
          const SizedBox(height: 8),
          _CopyableBox(
            key: const Key('detailPublicKey'),
            text: publicKey,
            onCopy: onCopyPublicKey,
            copyTooltip: 'Genel anahtarı kopyala',
            trailing: onExport == null
                ? null
                : Tooltip(
                    message: 'Genel anahtarı .pub dosyası olarak kaydet',
                    child: SecondaryButton(
                      key: const Key('detailExport'),
                      label: 'Dosyaya aktar…',
                      onPressed: onExport,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 12, color: c.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Özel anahtar güvenlik gereği hiçbir zaman gösterilmez veya '
                  'dışa aktarılmaz (ADR 0005).',
                  style: context.ui(size: 11, color: c.textDim),
                ),
              ),
            ],
          ),
        ],

        // ── Using connections ───────────────────────────────────────────────
        if (referencingConnections.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('Kullanan bağlantılar'),
          const SizedBox(height: 8),
          for (final conn in referencingConnections)
            _ConnectionLink(
              connection: conn,
              onTap: onJumpToConnection == null
                  ? null
                  : () => onJumpToConnection!(conn),
            ),
        ],

        // ── Danger ──────────────────────────────────────────────────────────
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: DangerButton(
            key: const Key('detailDelete'),
            label: 'Kimliği sil',
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: context.ui(size: 12.5, color: c.textDim)),
          ),
          Expanded(
            child: Text(
              value,
              style: context.ui(size: 12.5, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableBox extends StatelessWidget {
  final String text;
  final VoidCallback? onCopy;
  final String copyTooltip;
  final Widget? trailing;
  const _CopyableBox({
    super.key,
    required this.text,
    required this.onCopy,
    required this.copyTooltip,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: SelectableText(text, style: context.mono(size: 12)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: copyTooltip,
              child: SecondaryButton(label: 'Kopyala', onPressed: onCopy),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

class _ConnectionLink extends StatelessWidget {
  final Connection connection;
  final VoidCallback? onTap;
  const _ConnectionLink({required this.connection, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 14, color: c.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connection.label,
                  style: context.ui(
                    size: 12.5,
                    color: onTap == null ? c.text : c.accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 16, color: c.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
