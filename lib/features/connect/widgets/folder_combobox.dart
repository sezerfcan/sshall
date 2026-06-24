import 'package:flutter/material.dart';

import '../../../data/models/folder.dart';
import '../../../theme/context_ext.dart';

/// Dangling-ref-guarded folder picker (ADR 0031, D6). Reuses the safe dropdown
/// pattern from `folder_defaults_dialog._identityDropdown`: a value that no
/// longer matches any folder (deleted in another window) is surfaced as an
/// explicit "(missing)" item instead of tripping DropdownButton's
/// "value matches exactly one item" assertion and crashing the dialog.
///
/// Items: Kök (root, value null) + every folder. Carries §9 helper text.
/// Reusable so the edit dialog (ADR 0025) can adopt it later.
class FolderCombobox extends StatelessWidget {
  /// Selected folder id; null = root (no folder).
  final String? value;
  final List<Folder> folders;
  final ValueChanged<String?> onChanged;

  /// Optional helper line under the control (§9). null hides it.
  final String? helperText;

  const FolderCombobox({
    super.key,
    required this.value,
    required this.folders,
    required this.onChanged,
    this.helperText = 'Bu host\'un ait olacağı klasör (Kök = klasörsüz)',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final knownIds = folders.map((f) => f.id).toSet();
    // The selected folder may have been deleted elsewhere; surface it as an
    // explicit item so DropdownButton doesn't assert on an orphan value.
    final dangling = value != null && !knownIds.contains(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Klasör',
            style: context.ui(
              size: 12,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: const Key('folder'),
              value: value,
              isExpanded: true,
              dropdownColor: c.elevated,
              style: context.ui(size: 14),
              onChanged: onChanged,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Kök', style: context.ui(size: 14)),
                ),
                if (dangling)
                  DropdownMenuItem<String?>(
                    value: value,
                    child: Text(
                      '(eksik klasör — silinmiş)',
                      style: context.ui(size: 14, color: c.red),
                    ),
                  ),
                for (final f in folders)
                  DropdownMenuItem<String?>(
                    value: f.id,
                    child: Text(f.name, style: context.ui(size: 14)),
                  ),
              ],
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(helperText!, style: context.ui(size: 11.5, color: c.textDim)),
        ],
      ],
    );
  }
}
