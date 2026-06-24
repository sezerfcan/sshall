import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import 'identity_filter.dart';

/// Search + filter controls for the vault identity list (ADR 0033 / D6).
/// A text query (label / algorithm / fingerprint substring), a segmented type
/// filter, and an "unused-only" toggle. Every control carries a tooltip (§9).
class VaultSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final IdentityTypeFilter typeFilter;
  final bool unusedOnly;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<IdentityTypeFilter> onTypeChanged;
  final ValueChanged<bool> onUnusedChanged;

  const VaultSearchBar({
    super.key,
    required this.controller,
    required this.typeFilter,
    required this.unusedOnly,
    required this.onQueryChanged,
    required this.onTypeChanged,
    required this.onUnusedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message:
              'Etikete, algoritmaya ya da parmak izine göre ara. Sunucunun '
              'bildirdiği bir SHA256\'yı yapıştırıp yerel anahtarı bulabilirsin.',
          child: AppTextField(
            fieldKey: const Key('vaultSearch'),
            controller: controller,
            hintText: 'Ara: etiket, algoritma veya SHA256 parmak izi',
            onChanged: onQueryChanged,
            prefixIcon: Icon(Icons.search, size: 16, color: c.textDim),
          ),
        ),
        const SizedBox(height: 10),
        // Wrap (not Row) so the segments + toggle reflow on a narrow vault pane
        // instead of overflowing.
        Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Segmented type filter.
            for (final f in IdentityTypeFilter.values)
              _Segment(
                label: f.label,
                selected: typeFilter == f,
                onTap: () => onTypeChanged(f),
              ),
            // Unused-only toggle.
            Tooltip(
              message:
                  'Yalnızca hiçbir bağlantının kullanmadığı kimlikleri göster',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onUnusedChanged(!unusedOnly),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        unusedOnly
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 16,
                        color: unusedOnly ? c.accent : c.textDim,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Kullanılmayanlar',
                        style: context.ui(
                          size: 12,
                          weight: FontWeight.w600,
                          color: unusedOnly ? c.text : c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Text(
            label,
            style: context.ui(
              size: 12,
              weight: FontWeight.w600,
              color: selected ? c.accent : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
