import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../theme/app_colors.dart';
import '../../theme/context_ext.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/app_stepper.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_toggle.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_label.dart';
import '../../widgets/settings_row_tile.dart';
import '../shell/shell_overlay.dart';
import '../shell/shell_state.dart';
import '../shell/shortcuts_help_dialog.dart';
import '../terminal/terminal_session_controller.dart';
import '../vault/reset_vault_dialog.dart';
import 'app_settings.dart';
import 'app_version.dart';
import 'settings_row.dart';

/// Below this width the left nav collapses into a dropdown (ADR 0021 responsive
/// shell). Above it, the master/detail rail + detail pane sit side by side.
const double _navCollapseWidth = 620;

/// The sectioned master/detail settings surface (ADR 0038). A left nav lists the
/// groups (Görünüm / Terminal / Bağlantı / Davranış / Klavye Kısayolları /
/// Hakkında) plus a visually separated danger zone; the right pane scrolls the
/// selected group (or live search results). On narrow widths the nav collapses
/// into a dropdown. The single [SettingsRow] model feeds both the in-page search
/// and the render (D2/D3).
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  SettingsGroup _selected = SettingsGroup.appearance;
  bool _dangerSelected = false;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _searching => _query.trim().isNotEmpty;

  void _selectGroup(SettingsGroup g) {
    setState(() {
      _selected = g;
      _dangerSelected = false;
      _query = '';
      _searchController.clear();
    });
  }

  void _selectDanger() {
    setState(() {
      _dangerSelected = true;
      _query = '';
      _searchController.clear();
    });
  }

  /// Jump from a search result to its group (clears the search, ADR 0038 D2).
  void _jumpToGroup(SettingsGroup g) {
    setState(() {
      _selected = g;
      _dangerSelected = false;
      _query = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = _allRows();

    return LayoutBuilder(
      builder: (context, cons) {
        final narrow = cons.maxWidth < _navCollapseWidth;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ayarlar',
                style: context.ui(
                  size: 22,
                  weight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 14),
              _searchBox(context),
              const SizedBox(height: 14),
              Expanded(
                child: narrow
                    ? _narrowLayout(context, rows)
                    : _wideLayout(context, rows),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- search box ----------------------------------------------------------

  Widget _searchBox(BuildContext context) {
    final c = context.c;
    return AppTextField(
      controller: _searchController,
      fieldKey: const Key('settingsSearch'),
      hintText: 'Ayarlarda ara… (örn. port, tema, yazı tipi)',
      prefixIcon: Icon(Icons.search, size: 18, color: c.textMuted),
      suffixIcon: _searching
          ? IconButton(
              tooltip: 'Aramayı temizle',
              icon: Icon(Icons.close, size: 16, color: c.textMuted),
              onPressed: () => setState(() {
                _query = '';
                _searchController.clear();
              }),
            )
          : null,
      onChanged: (v) => setState(() => _query = v),
    );
  }

  // --- wide layout (nav rail + detail) -------------------------------------

  Widget _wideLayout(BuildContext context, List<SettingsRow> rows) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 196, child: _navRail(context)),
        const SizedBox(width: 16),
        Container(width: 1, color: c.border),
        const SizedBox(width: 16),
        Expanded(child: _detailPane(context, rows)),
      ],
    );
  }

  Widget _narrowLayout(BuildContext context, List<SettingsRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navDropdown(context),
        const SizedBox(height: 14),
        Expanded(child: _detailPane(context, rows)),
      ],
    );
  }

  // --- nav -----------------------------------------------------------------

  Widget _navRail(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in SettingsGroup.values)
          _NavItem(
            label: g.label,
            icon: g.icon,
            active: !_dangerSelected && _selected == g && !_searching,
            onTap: () => _selectGroup(g),
          ),
        const SizedBox(height: 8),
        Divider(color: c.border, height: 1),
        const SizedBox(height: 8),
        // Danger zone — visually separated, warning-tinted (D1/D10).
        _NavItem(
          label: 'Tehlikeli Bölge',
          icon: Icons.warning_amber_rounded,
          active: _dangerSelected,
          danger: true,
          onTap: _selectDanger,
        ),
      ],
    );
  }

  Widget _navDropdown(BuildContext context) {
    final c = context.c;
    // A single dropdown listing every group + the danger zone (ADR 0021). Value
    // is the index: 0..groups-1 = groups, last = danger zone.
    const groups = SettingsGroup.values;
    final selectedIndex = _dangerSelected
        ? groups.length
        : groups.indexOf(_selected);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: const Key('settingsNavDropdown'),
          value: selectedIndex,
          isExpanded: true,
          isDense: true,
          dropdownColor: c.elevated,
          icon: Icon(Icons.expand_more, size: 18, color: c.textMuted),
          onChanged: (i) {
            if (i == null) return;
            if (i == groups.length) {
              _selectDanger();
            } else {
              _selectGroup(groups[i]);
            }
          },
          items: [
            for (var i = 0; i < groups.length; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(groups[i].icon, size: 16, color: c.textMuted),
                    const SizedBox(width: 8),
                    Text(groups[i].label, style: context.ui(size: 13)),
                  ],
                ),
              ),
            DropdownMenuItem<int>(
              value: groups.length,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: c.red),
                  const SizedBox(width: 8),
                  Text(
                    'Tehlikeli Bölge',
                    style: context.ui(size: 13, color: c.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- detail pane ---------------------------------------------------------

  Widget _detailPane(BuildContext context, List<SettingsRow> rows) {
    if (_searching) return _searchResults(context, rows);
    if (_dangerSelected) {
      return const SingleChildScrollView(
        key: Key('settingsDetailScroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel('Tehlikeli Bölge'),
            SizedBox(height: 12),
            _DangerZone(),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      key: const Key('settingsDetailScroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(_selected.label),
          const SizedBox(height: 12),
          _groupBody(context, _selected, rows),
        ],
      ),
    );
  }

  Widget _groupBody(
    BuildContext context,
    SettingsGroup group,
    List<SettingsRow> rows,
  ) {
    if (group == SettingsGroup.appearance) return const _AppearanceSection();
    if (group == SettingsGroup.about) return const _AboutSection();
    final groupRows = rows.where((r) => r.group == group).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final r in groupRows) _renderRow(context, r)],
    );
  }

  Widget _searchResults(BuildContext context, List<SettingsRow> rows) {
    final c = context.c;
    final matched = filterRows(rows, _query);
    // Appearance + About rows are not in the row model (they render bespoke
    // widgets), but their group labels still surface via keyword hits below.
    if (matched.isEmpty) {
      return Center(
        key: const Key('settingsNoResults'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Eşleşen ayar yok.\nFarklı bir terim deneyin (etiket, açıklama veya bölüm adı).',
            textAlign: TextAlign.center,
            style: context.ui(size: 13, color: c.textMuted),
          ),
        ),
      );
    }
    // Group the matched rows by their owning group with a header per group, and
    // make each result tappable to jump to its group (D2).
    final byGroup = <SettingsGroup, List<SettingsRow>>{};
    for (final r in matched) {
      byGroup.putIfAbsent(r.group, () => []).add(r);
    }
    return SingleChildScrollView(
      key: const Key('settingsSearchResults'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in byGroup.entries) ...[
            InkWell(
              key: Key('searchGroup_${entry.key.name}'),
              onTap: () => _jumpToGroup(entry.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SectionLabel(entry.key.label),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 13, color: c.textDim),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final r in entry.value) _renderRow(context, r),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _renderRow(BuildContext context, SettingsRow r) {
    final control =
        r.control?.call(context) ??
        r.trailingBuilder?.call(context) ??
        const SizedBox.shrink();
    // Read-only rows (shortcuts) stack their binding on the right but never edit.
    final stack =
        r.group == SettingsGroup.connection && (r.id == 'defaultUsername');
    return SettingsRowTile(
      label: r.label,
      description: r.description,
      control: control,
      stackControl: stack,
    );
  }

  // --- the single row model (D2/D3) ----------------------------------------

  List<SettingsRow> _allRows() {
    final settings = ref.watch(appSettingsControllerProvider);
    final controller = ref.read(appSettingsControllerProvider.notifier);

    return [
      // Terminal (D5) ----------------------------------------------------
      SettingsRow(
        id: 'terminalFontSize',
        group: SettingsGroup.terminal,
        label: 'Yazı boyutu',
        description: 'Yeni terminal sekmeleri bu boyutta açılır.',
        keywords: const ['font', 'boyut', 'punto', 'büyüklük', 'terminal'],
        control: (_) => AppStepper(
          key: const Key('fontSizeStepper'),
          value: settings.terminalFontSize,
          min: kFontMin.toInt(),
          max: kFontMax.toInt(),
          semanticLabel: 'Terminal yazı boyutu',
          onChanged: controller.setTerminalFontSize,
        ),
      ),
      SettingsRow(
        id: 'terminalFontFamily',
        group: SettingsGroup.terminal,
        label: 'Yazı tipi',
        description: 'Terminal yazı tipi (monospace).',
        keywords: const ['font', 'yazı tipi', 'aile', 'monospace', 'jetbrains'],
        control: (_) => AppDropdown<String>(
          buttonKey: const Key('fontFamilyDropdown'),
          value: settings.terminalFontFamily,
          items: kMonospaceFamilies,
          labelOf: (s) => s,
          semanticLabel: 'Terminal yazı tipi',
          onChanged: controller.setTerminalFontFamily,
        ),
      ),

      // Connection (D6) --------------------------------------------------
      SettingsRow(
        id: 'defaultUsername',
        group: SettingsGroup.connection,
        label: 'Varsayılan kullanıcı adı',
        description: 'Yeni bağlantı formunda ön-doldurulur.',
        keywords: const ['kullanıcı', 'user', 'username', 'bağlantı'],
        control: (_) => SizedBox(
          width: 240,
          child: _DefaultUsernameField(
            value: settings.defaultUsername,
            onChanged: controller.setDefaultUsername,
          ),
        ),
      ),
      SettingsRow(
        id: 'defaultPort',
        group: SettingsGroup.connection,
        label: 'Varsayılan port',
        description: 'Yeni bağlantıda varsayılan SSH portu (genelde 22).',
        keywords: const ['port', '22', 'ssh', 'bağlantı'],
        control: (_) => SizedBox(
          width: 110,
          child: _DefaultPortField(
            value: settings.defaultPort,
            onChanged: controller.setDefaultPort,
          ),
        ),
      ),
      SettingsRow(
        id: 'keepAlive',
        group: SettingsGroup.connection,
        label: 'Keepalive aralığı',
        description: 'Boşta bağlantıyı canlı tutma aralığı (0: kapalı).',
        keywords: const ['keepalive', 'canlı', 'idle', 'bağlantı', 'saniye'],
        control: (_) => AppStepper(
          key: const Key('keepAliveStepper'),
          value: settings.keepAliveSeconds,
          min: 0,
          max: kKeepAliveMax,
          step: 5,
          unit: 'sn',
          semanticLabel: 'Keepalive aralığı (saniye)',
          onChanged: controller.setKeepAliveSeconds,
        ),
      ),

      // Behavior (D7) ----------------------------------------------------
      SettingsRow(
        id: 'confirmOnClose',
        group: SettingsGroup.behavior,
        label: 'Kapatmadan önce onay iste',
        description: 'Canlı bir oturum sekmesini kapatırken onay sorulur.',
        keywords: const ['onay', 'kapat', 'close', 'oturum', 'davranış'],
        control: (_) => AppToggle(
          key: const Key('confirmOnCloseToggle'),
          label: 'Canlı oturumu kapatmadan önce onay iste',
          value: settings.confirmOnCloseLiveSession,
          onChanged: controller.setConfirmOnCloseLiveSession,
        ),
      ),
      SettingsRow(
        id: 'openOnLaunch',
        group: SettingsGroup.behavior,
        label: 'Açılışta',
        description: 'Uygulama açıldığında ne gösterilsin.',
        keywords: const [
          'açılış',
          'launch',
          'başlangıç',
          'karşılama',
          'davranış',
        ],
        control: (_) => AppDropdown<OpenOnLaunch>(
          buttonKey: const Key('openOnLaunchDropdown'),
          value: settings.openOnLaunch,
          items: OpenOnLaunch.values,
          labelOf: (v) => v.label,
          semanticLabel: 'Açılışta gösterilecek ekran',
          onChanged: controller.setOpenOnLaunch,
        ),
      ),

      // Shortcuts (D8) — read-only, searchable -------------------------
      for (final (binding, desc) in kShortcutEntries)
        SettingsRow(
          id: 'shortcut_$binding',
          group: SettingsGroup.shortcuts,
          label: desc,
          description: 'Klavye kısayolu',
          keywords: [binding, desc],
          trailingBuilder: (ctx) => _ShortcutBadge(binding: binding),
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav item
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = danger ? c.red : c.accent;
    final fg = active ? accent : (danger ? c.red : c.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          key: Key('settingsNav_$label'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: active ? c.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? accent : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.ui(
                      size: 13,
                      weight: active ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default username field — local controller so typing persists per keystroke
// ─────────────────────────────────────────────────────────────────────────────

class _DefaultUsernameField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _DefaultUsernameField({required this.value, required this.onChanged});

  @override
  State<_DefaultUsernameField> createState() => _DefaultUsernameFieldState();
}

class _DefaultUsernameFieldState extends State<_DefaultUsernameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_DefaultUsernameField old) {
    super.didUpdateWidget(old);
    // Reflect an external value change (e.g. "Tüm ayarları sıfırla" while the
    // Settings pane is open) without fighting the user's active edit: only
    // overwrite when the incoming value actually differs from what the field
    // already shows, which preserves the caret during normal typing.
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      fieldKey: const Key('defaultUsernameField'),
      hintText: 'örn. root',
      onChanged: widget.onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default port field — small numeric text field (digits only, 1–65535).
// Replaces the unit-step stepper so reaching a non-22 port like 2222 is a
// single keystroke set, mirroring the connect dialog's port field. Empty input
// falls back to the canonical default (22); the setter clamps the valid range.
// ─────────────────────────────────────────────────────────────────────────────

class _DefaultPortField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _DefaultPortField({required this.value, required this.onChanged});

  @override
  State<_DefaultPortField> createState() => _DefaultPortFieldState();
}

class _DefaultPortFieldState extends State<_DefaultPortField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toString(),
  );

  @override
  void didUpdateWidget(_DefaultPortField old) {
    super.didUpdateWidget(old);
    // Mirror an external value change (e.g. reset-settings) without disturbing
    // an in-progress edit: only overwrite when the parsed field value differs
    // from the incoming setting.
    if (int.tryParse(_controller.text) != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final text = raw.trim();
    // Empty → fall back to the canonical default (22) without churning the
    // field text, so the user can keep deleting/typing.
    if (text.isEmpty) {
      widget.onChanged(kDefaultPort);
      return;
    }
    final parsed = int.tryParse(text);
    // The setter itself rejects out-of-range values (kPortMin..kPortMax), so an
    // over-long entry simply leaves the stored port unchanged.
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      fieldKey: const Key('defaultPortField'),
      hintText: '22',
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: _onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shortcut badge (read-only binding)
// ─────────────────────────────────────────────────────────────────────────────

class _ShortcutBadge extends StatelessWidget {
  final String binding;
  const _ShortcutBadge({required this.binding});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Text(binding, style: context.mono(size: 12, color: c.text)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appearance section — theme cards (D4)
// ─────────────────────────────────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeControllerProvider);
    // Theme set + order + labels come from the SAME canonical source
    // (AppThemeId.values + AppThemeIdLabel.label) that the title-bar popup's
    // shared ThemePickerMenu uses, so the two pickers can never drift (ADR 0039
    // D4). This surface renders the richer card grid (component 9, ADR 0038);
    // only the underlying entry data is shared, not the layout.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uygulamanın renk teması. Seçili tema tüm pencerelere uygulanır.',
          style: context.ui(size: 12.5, color: context.c.textMuted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppThemeId.values.map((id) {
            return _ThemeCard(
              id: id,
              isActive: id == currentTheme,
              onTap: () => ref.read(themeControllerProvider.notifier).set(id),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeId id;
  final bool isActive;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.id,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final palette = AppColors.of(id);

    return Tooltip(
      message: id.label,
      child: GestureDetector(
        key: Key('themeCard_${id.name}'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // No fixed width + ellipsis anymore — the card sizes to fit the full
          // canonical label so 'Green Terminal'/'Gece (Tokyo Night)' never clip.
          width: 170,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // Stronger selected state: a subtle accent bg tint (D4).
            color: isActive ? c.accentSoft : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? c.accent : c.border,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PalettePreview(palette: palette),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Single canonical label source (AppThemeIdLabel) — the
                      // title-bar popup shares it, so they never drift (D4).
                      id.label,
                      softWrap: true,
                      style: context.ui(
                        size: 12,
                        weight: FontWeight.w600,
                        color: isActive ? c.accent : c.textMuted,
                      ),
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_circle_rounded, size: 15, color: c.accent),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PalettePreview extends StatelessWidget {
  final AppColors palette;
  const _PalettePreview({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 20,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.elevated,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              const Expanded(flex: 3, child: SizedBox()),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            _Dot(palette.accent),
            const SizedBox(width: 4),
            _Dot(palette.accent2),
            const SizedBox(width: 4),
            _Dot(palette.green),
            const SizedBox(width: 4),
            _Dot(palette.border),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// About section — runtime version + clickable links (D9)
// ─────────────────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 18, color: c.accent),
              const SizedBox(width: 8),
              // Runtime version (package_info_plus) — no hard-coded 'v0.3.0'.
              FutureBuilder<String>(
                future: appVersionLabel(),
                builder: (context, snap) => Text(
                  snap.data ?? '$kAppName $kAppVersion',
                  key: const Key('aboutVersion'),
                  style: context.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'MIT License · açık kaynak · Flutter ile geliştirildi.',
            style: context.ui(size: 12.5, color: c.textMuted),
          ),
          const SizedBox(height: 14),
          const _LinkRow(
            icon: Icons.code_rounded,
            label: 'Depo (GitHub)',
            url: 'https://github.com/sshall/sshall',
            linkKey: Key('aboutLinkRepo'),
          ),
          const _LinkRow(
            icon: Icons.description_outlined,
            label: 'Lisans (MIT)',
            url: 'https://github.com/sshall/sshall/blob/main/LICENSE',
            linkKey: Key('aboutLinkLicense'),
          ),
          const _LinkRow(
            icon: Icons.history_rounded,
            label: 'Değişiklik günlüğü (Changelog)',
            url:
                'https://github.com/sshall/sshall/blob/main/docs/progress/CHANGELOG.md',
            linkKey: Key('aboutLinkChangelog'),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  final Key linkKey;
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.linkKey,
  });

  Future<void> _open() async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: url,
      child: InkWell(
        key: linkKey,
        borderRadius: BorderRadius.circular(6),
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 15, color: c.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: context.ui(
                  size: 13,
                  weight: FontWeight.w500,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 13, color: c.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Danger zone — reset-settings (lesser, amber) + reset-vault (strongest, red)
// ─────────────────────────────────────────────────────────────────────────────

class _DangerZone extends ConsumerWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // (1) Reset settings — LESSER severity (amber warning), vault untouched.
        _DangerCard(
          accent: c.amber,
          title: 'Tüm ayarları sıfırla',
          body:
              'Yalnızca uygulama tercihlerini (tema hariç ayar grupları) '
              'varsayılana döndürür. Vault ve kayıtlı bağlantılarınız '
              'etkilenmez.',
          button: _WarningButton(
            key: const Key('settingsResetSettings'),
            label: 'Tüm ayarları sıfırla',
            onPressed: () => _resetSettings(context, ref),
          ),
        ),
        const SizedBox(height: 14),
        // (2) Reset vault — STRONGEST destructive action (preserved type-SIFIRLA).
        _DangerCard(
          accent: c.red,
          title: "Vault'u sıfırla",
          body:
              "Tüm kayıtlı bağlantı, kimlik, klasör ve host-key kayıtlarınızı "
              "kalıcı olarak siler ve sizi yeni vault oluşturma ekranına "
              "döndürür. Master passphrase olmadan veriler kurtarılamaz; bu işlem "
              "GERİ ALINAMAZ.",
          button: DangerButton(
            key: const Key('settingsResetVault'),
            label: "Vault'u sıfırla",
            onPressed: () => _resetVault(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _resetSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.c;
        return AlertDialog(
          backgroundColor: c.elevated,
          title: Text(
            'Tüm ayarları sıfırla',
            style: ctx.ui(size: 16, weight: FontWeight.w600),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              'Tüm uygulama tercihleri varsayılana döner. '
              'Vault ve kayıtlı bağlantılarınız ETKİLENMEZ.',
              style: ctx.ui(size: 13, color: c.textMuted),
            ),
          ),
          actions: [
            GhostButton(
              label: 'Vazgeç',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            _WarningButton(
              key: const Key('confirmResetSettings'),
              label: 'Sıfırla',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    ref.read(appSettingsControllerProvider.notifier).reset();
  }

  Future<void> _resetVault(BuildContext context, WidgetRef ref) async {
    final confirmed = await showResetVaultDialog(context);
    if (!confirmed) return;
    try {
      final store = await ref.read(secureStoreProvider.future);
      final r = await store.reset();
      if (r.isOk) {
        await ref.read(tabsControllerProvider.notifier).closeAll();
        ref.read(selectedConnectionProvider.notifier).state = null;
        ref.read(expandedFoldersProvider.notifier).state = <String>{};
        ref.read(sidebarSearchProvider.notifier).state = '';
        ref.read(activeOverlayProvider.notifier).state = ShellOverlay.none;
        ref.read(homeRequestedProvider.notifier).state = false;
        ref.read(sessionUnlockedProvider.notifier).state = false;
      }
    } catch (_) {
      // reset() returns a typed Result; this only guards a provider/IO error.
    }
  }
}

class _DangerCard extends StatelessWidget {
  final Color accent;
  final String title;
  final String body;
  final Widget button;
  const _DangerCard({
    required this.accent,
    required this.title,
    required this.body,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: context.ui(
                  size: 14,
                  weight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: context.ui(size: 13, color: c.textMuted)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: button),
        ],
      ),
    );
  }
}

/// A warning-severity button (amber) for the lesser reset-settings action —
/// visually weaker than [DangerButton] (red) so the vault reset stays strongest.
class _WarningButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _WarningButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: c.amber.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.amber),
          ),
          child: Text(
            label,
            style: context.ui(
              size: 13,
              weight: FontWeight.w600,
              color: c.amber,
            ),
          ),
        ),
      ),
    );
  }
}
