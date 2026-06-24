import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/context_ext.dart';

/// The single canonical theme-picker surface (ADR 0039 D4).
///
/// Both the title-bar theme popup AND any Settings menu-form render from THIS
/// widget, so the order ([AppThemeId.values]), the labels ([AppThemeIdLabel])
/// and the selected marker can never drift between the two entry points.
///
/// It exposes two shapes built from the same source:
///   * [row] — one entry (colour preview dot + canonical label + ✓ marker),
///     used inside a [PopupMenuItem]; and
///   * [items] — the full ordered list of [PopupMenuItem]s, so a popup can be
///     wired with one call.
class ThemePickerMenu {
  const ThemePickerMenu._();

  /// One canonical theme entry: colour preview dot + label + current marker.
  /// Shared by every theme-picker so the row layout cannot diverge.
  static Widget row(BuildContext context, AppThemeId id, AppThemeId current) {
    final c = context.c;
    return Row(
      children: [
        Container(
          key: Key('themeSwatch_${id.name}'),
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: AppColors.of(id).accent,
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            id.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.ui(size: 12.5),
          ),
        ),
        if (id == current) ...[
          const SizedBox(width: 8),
          Icon(Icons.check, size: 14, color: c.accent),
        ],
      ],
    );
  }

  /// The full ordered list of theme [PopupMenuItem]s (one per [AppThemeId]),
  /// each carrying [id] as its value and rendering the canonical [row]. A popup
  /// builder can return this directly so the title-bar and Settings menu-form
  /// share the exact same entries.
  static List<PopupMenuEntry<AppThemeId>> items(
    BuildContext context,
    AppThemeId current,
  ) => [
    for (final id in AppThemeId.values)
      PopupMenuItem<AppThemeId>(
        value: id,
        height: 38,
        child: row(context, id, current),
      ),
  ];
}
