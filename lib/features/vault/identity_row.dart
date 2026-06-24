import 'package:flutter/material.dart';

import '../../data/models/identity.dart';
import '../../theme/context_ext.dart';
import '../../widgets/tag.dart';
import 'identity_view_model.dart';
import 'vault_format.dart';

/// Quick actions in an identity row's trailing kebab (ADR 0033 / D2).
enum IdentityRowAction {
  copyPublicKey,
  copyFingerprint,
  rename,
  export,
  delete,
}

/// One interactive identity row: type icon → label → REAL algorithm tag →
/// usage badge → truncated SHA256 fingerprint (mono, tooltip = full) → kebab.
///
/// The whole row is clickable (opens the detail view). PASSWORD rows omit the
/// fingerprint cell entirely (no dead '—' — D2). No secret material is read
/// here; only the NON-SECRET [IdentityView] projection (ADR 0005 / 0033).
class IdentityRow extends StatelessWidget {
  final IdentityView view;
  final int usage;
  final VoidCallback onOpen;
  final ValueChanged<IdentityRowAction> onAction;

  const IdentityRow({
    super.key,
    required this.view,
    required this.usage,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isKey = view.isKey;
    final fp = view.fingerprint;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(
                isKey ? Icons.vpn_key_outlined : Icons.password_outlined,
                size: 16,
                color: c.textMuted,
              ),
              const SizedBox(width: 12),
              // Label takes most of the remaining width but yields to the
              // fingerprint cell when space is tight (flex 3 vs 2), so neither
              // overflows on a narrow vault pane.
              Flexible(
                flex: 3,
                child: Text(
                  view.identity.label,
                  style: context.ui(size: 13, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              // REAL algorithm tag — replaces the old generic 'Anahtar' tag.
              Tag(text: view.algorithmLabel),
              const SizedBox(width: 10),
              _UsageBadge(usage: usage),
              // Fingerprint cell — keys only. Password rows skip it (no '—').
              if (fp != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  flex: 2,
                  child: _FingerprintCell(
                    fingerprint: fp,
                    onCopy: () => onAction(IdentityRowAction.copyFingerprint),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              _Kebab(view: view, onAction: onAction),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageBadge extends StatelessWidget {
  final int usage;
  const _UsageBadge({required this.usage});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final used = usage > 0;
    final text = used ? '$usage bağlantı' : 'Kullanılmıyor';
    return Tooltip(
      message: used
          ? 'Bu kimliği $usage bağlantı/klasör kullanıyor'
          : 'Bu kimliği hiçbir bağlantı kullanmıyor',
      child: Text(
        text,
        style: context.ui(
          size: 11,
          weight: FontWeight.w600,
          color: used ? c.textMuted : c.textDim,
        ),
      ),
    );
  }
}

class _FingerprintCell extends StatelessWidget {
  final String fingerprint;
  final VoidCallback onCopy;
  const _FingerprintCell({required this.fingerprint, required this.onCopy});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message:
          'Bu anahtarın SHA256 parmak izi (sunucudaki anahtarla karşılaştır)\n$fingerprint',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ellipsize when the pane is narrow so the row never overflows; the
          // full value is always available on the tooltip.
          Flexible(
            child: Text(
              shortFingerprint(fingerprint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mono(size: 11, color: c.textDim),
            ),
          ),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onCopy,
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.copy_outlined, size: 13, color: c.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kebab extends StatelessWidget {
  final IdentityView view;
  final ValueChanged<IdentityRowAction> onAction;
  const _Kebab({required this.view, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isKey = view.identity.type == IdentityType.privateKey;
    return Tooltip(
      message: 'Hızlı eylemler',
      child: PopupMenuButton<IdentityRowAction>(
        icon: Icon(Icons.more_vert, size: 18, color: c.textMuted),
        tooltip: '',
        color: c.elevated,
        onSelected: onAction,
        itemBuilder: (context) => [
          // Public-key actions only make sense for keys (NON-SECRET, ADR 0005).
          if (isKey) ...[
            _item(
              context,
              IdentityRowAction.copyPublicKey,
              Icons.vpn_key_outlined,
              'Genel anahtarı kopyala',
            ),
            _item(
              context,
              IdentityRowAction.copyFingerprint,
              Icons.fingerprint,
              'Parmak izini kopyala',
            ),
          ],
          _item(
            context,
            IdentityRowAction.rename,
            Icons.edit_outlined,
            'Yeniden adlandır',
          ),
          if (isKey)
            _item(
              context,
              IdentityRowAction.export,
              Icons.download_outlined,
              'Dışa aktar…',
            ),
          _item(
            context,
            IdentityRowAction.delete,
            Icons.delete_outline,
            'Sil',
            danger: true,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<IdentityRowAction> _item(
    BuildContext context,
    IdentityRowAction value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final c = context.c;
    final color = danger ? c.red : c.text;
    return PopupMenuItem<IdentityRowAction>(
      value: value,
      height: 38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: context.ui(size: 13, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
