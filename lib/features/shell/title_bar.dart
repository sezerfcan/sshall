import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/context_ext.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/theme_picker_menu.dart';
import '../settings/app_version.dart';
import 'shell_overlay.dart';
import 'shell_responsive.dart';
import 'shell_state.dart';
import 'shortcuts_help_dialog.dart';
import 'window_chrome.dart';

/// The top window bar — a unified title + toolbar (ADR 0039). A calm, balanced
/// chrome (ADR 0009 tokens only — no hard-coded colours):
///   * brand on the left (terminal glyph + 'sshall' wordmark + runtime version
///     badge);
///   * the CENTERED active-session title in the middle (quiet, inert, inside the
///     drag region — empty on the home surface, never a fake title); and
///   * a lean, consistent trailing cluster on the right
///     `[Klavye kısayolları] [Tema] [Ayarlar] [⋯]`, every control a single 28px
///     hit target with a tooltip ending in its shortcut.
///
/// It adapts to the window width (ADR 0021/0039 D5): as the window narrows it
/// drops, in order, the version badge → the centered title (middle-ellipsis,
/// then gone) → the Settings gear into "⋯" → then the whole trailing cluster
/// into "⋯" → finally the wordmark (icon only). Every action stays reachable —
/// hidden controls move into the overflow menu, never disappear.
class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final chrome = ref.read(windowChromeProvider);

    // The OS window-title mirror (ADR 0039 D1) is driven from AppShell's
    // lifecycle (a `listenManual` in initState) so it also fires for the initial
    // value and never runs as a side effect of this stateless build.
    final activeTitle = ref.watch(activeSessionTitleProvider);

    // In macOS fullscreen the native traffic lights are hidden, so the left
    // gutter collapses to zero instead of reserving 78px of dead space (ADR 0039
    // D5). Reactive: flips on window_manager's enter/leave-fullscreen events,
    // defaults to false under flutter_test.
    final isFullScreen = ref.watch(fullScreenProvider);
    final gutter = ShellBreakpoints.macTrafficLightGutter(
      isFullScreen: isFullScreen,
    );

    return GestureDetector(
      key: const Key('titleBarDrag'),
      behavior: HitTestBehavior.translucent,
      // Drag anywhere on the bar to move the OS window (ADR 0024). A pan
      // recognizer rejects on a tap-without-movement, so it never delays the
      // bar's buttons. Double-click-to-zoom lives on the empty filler only (the
      // centered-title region below) — an ancestor onDoubleTap here would *hold*
      // the gesture arena for the double-tap timeout and lag every button tap.
      onPanStart: (_) => chrome.startDragging(),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        padding: EdgeInsets.only(
          left: gutter,
          right: 10,
        ), // left gutter: native macOS traffic lights (zero in fullscreen)
        child: LayoutBuilder(
          builder: (context, cons) {
            // The bar spans the window; add back the fixed padding (gutter + 10)
            // so the breakpoints read in window-width terms regardless of insets.
            final windowWidth = cons.maxWidth + gutter + 10;
            final showVersion = ShellBreakpoints.showVersion(windowWidth);
            final overflow = ShellBreakpoints.titleNeedsOverflow(windowWidth);
            final showWordmark = ShellBreakpoints.showWordmark(windowWidth);
            final showTitle = ShellBreakpoints.showTitle(windowWidth);
            // The Settings gear folds into "⋯" before the rest of the cluster.
            final settingsInOverflow = ShellBreakpoints.titleSettingsOverflow(
              windowWidth,
            );

            return Row(
              children: [
                // --- brand cluster (fixed priority, never yields) ---
                Icon(Icons.terminal, size: 15, color: c.accent),
                if (showWordmark) ...[
                  const SizedBox(width: 8),
                  Text(
                    'sshall',
                    style: context.ui(size: 13, weight: FontWeight.w700),
                  ),
                ],
                if (showVersion) ...[
                  const SizedBox(width: 10),
                  _versionBadge(context),
                ],
                // --- centered active-session title (flexible — yields first) ---
                // Takes the remaining flexible space and doubles as the
                // double-click-to-zoom / drag region. It optically centers the
                // (muted) session title on the wordmark baseline (D1/D6); on the
                // home surface it shows nothing (never a fake title).
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () => chrome.toggleMaximize(),
                    child: Center(
                      child: (showTitle && activeTitle != null)
                          ? _centeredTitle(context, activeTitle)
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
                // --- trailing cluster (fixed priority, 28px / 8px gaps) ---
                if (overflow)
                  // The WHOLE cluster has collapsed: the "⋯" carries help +
                  // theme + Settings (full superset — §9).
                  _overflowMenu(context, ref, wholeCluster: true)
                else ...[
                  _helpButton(context),
                  const SizedBox(width: 8),
                  _themeButton(context, ref),
                  const SizedBox(width: 8),
                  if (settingsInOverflow)
                    // Only the Settings gear has folded so far: the "⋯" carries
                    // just Settings (help + theme stay inline).
                    _overflowMenu(context, ref, wholeCluster: false)
                  else
                    _settingsButton(context, ref),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// The centered active-session title: quieter than the wordmark (textMuted,
  /// ~12.5px w600), middle-ellipsized for long hosts, inert (the surrounding
  /// drag/zoom gestures pass through). IgnorePointer keeps it from swallowing
  /// the drag region's pan/double-tap (D1). A Tooltip carries the FULL title so
  /// an ellipsized long host can still be read in full on hover;
  /// it sits OUTSIDE the IgnorePointer so hover is detected, yet its MouseRegion
  /// never absorbs the drag/zoom pointer events (verified by the D1 drag tests).
  Widget _centeredTitle(BuildContext context, String title) {
    final c = context.c;
    final label = Text(
      middleEllipsis(title, 42),
      key: const Key('titleActiveSession'),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: context.ui(size: 12.5, weight: FontWeight.w600, color: c.textMuted),
    );
    final inert = IgnorePointer(child: label);
    // Only attach the tooltip when there is a real title to reveal (the callsite
    // already gates on a non-null title; this also drops empty/whitespace).
    return title.trim().isEmpty
        ? inert
        : Tooltip(message: title, child: inert);
  }

  // Secondary build info, kept quiet (ADR 0009): a subtle bordered badge so it
  // reads as metadata, separated from the brand rather than crowding it. The
  // version is sourced at RUNTIME (package_info_plus) from the SAME helper the
  // About card uses, so the two never drift (ADR 0038 D9). Falls back to the
  // centralized kAppVersion constant if package_info_plus ever fails.
  Widget _versionBadge(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.border),
      ),
      child: FutureBuilder<String>(
        future: appVersionBadge(),
        builder: (context, snap) => Text(
          snap.data ?? 'v$kAppVersion',
          key: const Key('titleVersionBadge'),
          style: context.ui(
            size: 10.5,
            weight: FontWeight.w500,
            color: c.textDim,
          ),
        ),
      ),
    );
  }

  // Discoverable keyboard-shortcut / interaction reference. The
  // tooltip ends in its shortcut (D3).
  Widget _helpButton(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: 'Klavye kısayolları  ?',
      child: _BarHoverButton(
        buttonKey: const Key('shortcutsHelpButton'),
        onTap: () => showShortcutsHelpDialog(context),
        child: Icon(Icons.keyboard_outlined, size: 16, color: c.textMuted),
      ),
    );
  }

  // Single, quiet theme control. The palette icon is tinted with the ACTIVE
  // theme's accent — so the button shows the current theme at a glance — and a
  // caret signals the popup. The popup renders from the SHARED canonical
  // theme-picker (ThemePickerMenu) so it can never drift from Settings (D4).
  Widget _themeButton(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final current = ref.watch(themeControllerProvider);
    return Tooltip(
      message: 'Tema: ${current.label}',
      child: PopupMenuButton<AppThemeId>(
        key: const Key('themeButton'),
        tooltip: '',
        position: PopupMenuPosition.under,
        color: c.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        onSelected: (id) => ref.read(themeControllerProvider.notifier).set(id),
        itemBuilder: (context) => ThemePickerMenu.items(context, current),
        child: _BarHoverButton.chip(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.palette_outlined, size: 15, color: c.accent),
              const SizedBox(width: 5),
              Icon(Icons.expand_more, size: 15, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  // Direct entry to the Settings overlay (ADR 0039 D2) — the same surface ⌘, /
  // Ctrl+, opens. The tooltip ends in its platform-aware shortcut (D3/§9).
  Widget _settingsButton(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Tooltip(
      message: 'Ayarlar  $_settingsShortcutGlyph',
      child: _BarHoverButton(
        buttonKey: const Key('settingsButton'),
        onTap: () => ref.read(activeOverlayProvider.notifier).state =
            ShellOverlay.settings,
        child: Icon(Icons.settings_outlined, size: 16, color: c.textMuted),
      ),
    );
  }

  // Narrow window: the trailing controls that have folded collapse here so
  // nothing is lost (full superset). [wholeCluster] tells the
  // menu which folded controls to carry: when true the WHOLE cluster has
  // collapsed (help + theme + Settings); when false only the Settings gear has
  // folded so far (help + theme are still inline) so the menu carries Settings.
  Widget _overflowMenu(
    BuildContext context,
    WidgetRef ref, {
    required bool wholeCluster,
  }) {
    final c = context.c;
    final current = ref.watch(themeControllerProvider);
    return Tooltip(
      message: 'Daha fazla',
      child: PopupMenuButton<_TitleAction>(
        key: const Key('titleOverflowButton'),
        tooltip: '',
        padding: EdgeInsets.zero,
        color: c.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        icon: Icon(Icons.more_horiz, size: 18, color: c.textMuted),
        onSelected: (a) => a.run(context, ref),
        itemBuilder: (context) =>
            _overflowItems(context, current, includeHelpAndTheme: wholeCluster),
      ),
    );
  }

  List<PopupMenuEntry<_TitleAction>> _overflowItems(
    BuildContext context,
    AppThemeId current, {
    required bool includeHelpAndTheme,
  }) {
    return [
      if (includeHelpAndTheme)
        _overflowRow(
          context,
          _HelpAction(),
          Icons.keyboard_outlined,
          'Klavye kısayolları',
        ),
      // Settings is always present in the overflow (it is the FIRST trailing
      // control to fold — D5), so the menu is a true superset of hidden actions.
      _overflowRow(
        context,
        _SettingsAction(),
        Icons.settings_outlined,
        'Ayarlar',
      ),
      if (includeHelpAndTheme) ...[
        const PopupMenuDivider(),
        for (final id in AppThemeId.values)
          PopupMenuItem<_TitleAction>(
            value: _ThemeAction(id),
            height: 36,
            child: ThemePickerMenu.row(context, id, current),
          ),
      ],
    ];
  }

  PopupMenuItem<_TitleAction> _overflowRow(
    BuildContext context,
    _TitleAction action,
    IconData icon,
    String label,
  ) {
    final c = context.c;
    return PopupMenuItem<_TitleAction>(
      value: action,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 15, color: c.textMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Platform-aware glyph for the Settings shortcut (macOS ⌘, elsewhere Ctrl).
String get _settingsShortcutGlyph {
  // Web/desktop: only macOS uses ⌘; Windows/Linux use Ctrl.
  try {
    return Platform.isMacOS ? '⌘,' : 'Ctrl+,';
  } catch (_) {
    return '⌘,';
  }
}

/// Middle-ellipsis a long title so both ends stay legible (e.g. a long host:
/// "web-frontend-…-eu-west-1"). Pure → unit-tested. [max] is the maximum number
/// of characters; below it the string is returned unchanged.
String middleEllipsis(String text, int max) {
  if (max <= 1 || text.length <= max) return text;
  const ellipsis = '…';
  final keep = max - ellipsis.length;
  final head = (keep / 2).ceil();
  final tail = keep - head;
  return '${text.substring(0, head)}$ellipsis${text.substring(text.length - tail)}';
}

/// A small, hover-aware bar button. Two flavours: a bare icon (default) or a
/// bordered "chip" (used for the theme control). Both share ONE 28px hit target
/// (ADR 0039 D3); hover brightens the background with theme tokens only
/// (ADR 0009) so every trailing action feels consistent.
class _BarHoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Key? buttonKey;
  final bool chipStyle;

  const _BarHoverButton({required this.child, this.onTap, this.buttonKey})
    : chipStyle = false;

  const _BarHoverButton.chip({required this.child})
    : onTap = null,
      buttonKey = null,
      chipStyle = true;

  @override
  State<_BarHoverButton> createState() => _BarHoverButtonState();
}

class _BarHoverButtonState extends State<_BarHoverButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      // One consistent 28px hit target for every trailing control — the theme
      // chip no longer sits 2px shorter than the bare icons (ADR 0039 D3).
      height: 28,
      padding: EdgeInsets.symmetric(horizontal: widget.chipStyle ? 8 : 6),
      decoration: BoxDecoration(
        color: widget.chipStyle
            ? (_hovering ? c.elevated : c.surface2)
            : (_hovering ? c.surface2 : Colors.transparent),
        borderRadius: BorderRadius.circular(7),
        border: widget.chipStyle
            ? Border.all(color: _hovering ? c.borderStrong : c.border)
            : null,
      ),
      alignment: Alignment.center,
      child: widget.child,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      // The theme chip's tap is owned by the parent PopupMenuButton; the bare
      // icon variant handles its own tap.
      child: widget.onTap == null
          ? content
          : GestureDetector(
              key: widget.buttonKey,
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: content,
            ),
    );
  }
}

/// An action chosen from the title bar's overflow menu (ADR 0021/0039).
sealed class _TitleAction {
  void run(BuildContext context, WidgetRef ref);
}

class _HelpAction extends _TitleAction {
  @override
  void run(BuildContext context, WidgetRef ref) =>
      showShortcutsHelpDialog(context);
}

class _SettingsAction extends _TitleAction {
  @override
  void run(BuildContext context, WidgetRef ref) =>
      ref.read(activeOverlayProvider.notifier).state = ShellOverlay.settings;
}

class _ThemeAction extends _TitleAction {
  final AppThemeId id;
  _ThemeAction(this.id);
  @override
  void run(BuildContext context, WidgetRef ref) =>
      ref.read(themeControllerProvider.notifier).set(id);
}
