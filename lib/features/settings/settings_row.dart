import 'package:flutter/material.dart';

/// The settings sections shown in the master/detail nav (ADR 0038 D1). Each
/// group owns ONE canonical Turkish label shared by the nav, the in-page search
/// results and the detail-pane header (D11) — so they never drift.
enum SettingsGroup {
  appearance,
  terminal,
  connection,
  behavior,
  shortcuts,
  about,
}

extension SettingsGroupLabel on SettingsGroup {
  /// The single canonical Turkish label for this group.
  String get label => switch (this) {
    SettingsGroup.appearance => 'Görünüm',
    SettingsGroup.terminal => 'Terminal',
    SettingsGroup.connection => 'Bağlantı',
    SettingsGroup.behavior => 'Davranış',
    SettingsGroup.shortcuts => 'Klavye Kısayolları',
    SettingsGroup.about => 'Hakkında',
  };

  /// The nav icon for this group (icon controls get a label/tooltip — §9).
  IconData get icon => switch (this) {
    SettingsGroup.appearance => Icons.palette_outlined,
    SettingsGroup.terminal => Icons.terminal_rounded,
    SettingsGroup.connection => Icons.lan_outlined,
    SettingsGroup.behavior => Icons.tune_rounded,
    SettingsGroup.shortcuts => Icons.keyboard_outlined,
    SettingsGroup.about => Icons.info_outline_rounded,
  };
}

/// One setting as data (ADR 0038 D2/D3): a [label] + one-line [description] +
/// search [keywords] + owning [group] + a [control] builder. BOTH the in-page
/// search and the detail render read from this single model, so a row can never
/// be searchable but unrenderable (or vice versa).
class SettingsRow {
  final String label;
  final String description;
  final List<String> keywords;
  final SettingsGroup group;

  /// Builds the right-aligned control (AppToggle / AppTextField / stepper /
  /// dropdown). Null for a read-only informational row (e.g. a shortcut entry
  /// renders its binding via [trailingBuilder] instead).
  final WidgetBuilder? control;

  /// Optional trailing widget for read-only rows (shortcuts list, about links).
  final WidgetBuilder? trailingBuilder;

  /// A stable key used by search "jump to group" scrolling.
  final String id;

  const SettingsRow({
    required this.id,
    required this.label,
    required this.description,
    required this.group,
    this.keywords = const [],
    this.control,
    this.trailingBuilder,
  });

  /// Whether [query] matches this row's label, description or keywords
  /// (case-insensitive substring). An empty query matches everything.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (label.toLowerCase().contains(q)) return true;
    if (description.toLowerCase().contains(q)) return true;
    for (final k in keywords) {
      if (k.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// Pure filter shared by search + render (ADR 0038 D2). Returns the rows whose
/// label/description/keywords match [query] (case-insensitive substring). An
/// empty/whitespace query returns every row.
List<SettingsRow> filterRows(List<SettingsRow> rows, String query) {
  final q = query.trim();
  if (q.isEmpty) return List.of(rows);
  return rows.where((r) => r.matches(q)).toList();
}
