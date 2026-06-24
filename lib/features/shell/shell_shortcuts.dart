import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/terminal_session_controller.dart';
import 'close_tab_confirm.dart';
import 'shell_destinations.dart';
import 'shell_overlay.dart';
import 'shell_state.dart';

/// Shell-wide keyboard shortcuts (ADR 0018). Extracted from [AppShell] into its
/// own widget so the full VS Code-style key map can be exercised in isolation.
/// Wraps [child] with [CallbackShortcuts] + an autofocused [Focus] so a key
/// event anywhere in the shell reaches these bindings.
class ShellShortcuts extends ConsumerWidget {
  final Widget child;
  const ShellShortcuts({super.key, required this.child});

  void _closeActive(BuildContext context, WidgetRef ref) {
    final t = ref.read(tabsControllerProvider).activeTab;
    // Route ⌘W through the shared confirm gate so closing a live session prompts
    // when the setting is on (ADR 0038 D7).
    if (t != null) unawaited(closeTabWithConfirm(context, ref, t.id));
  }

  void _zoomActive(WidgetRef ref, void Function(TerminalSessionController) f) {
    final t = ref.read(tabsControllerProvider).activeTab;
    if (t == null || t.kind != TabKind.terminal) return;
    final ctrl = ref.read(tabsControllerProvider.notifier).controllerFor(t.id);
    if (ctrl != null) f(ctrl);
  }

  void _toggleSidebar(WidgetRef ref) =>
      ref.read(sidebarControllerProvider.notifier).toggle();

  /// Open the new-session launcher (home/welcome) — the SAME path as the strip
  /// "+" button and double-tap-empty (ADR 0036 D1). Does NOT persist anything.
  void _newTab(WidgetRef ref) =>
      ref.read(homeRequestedProvider.notifier).state = true;

  // Open the Settings overlay (⌘/Ctrl+,). Esc (handled inside the overlay)
  // closes it (ADR 0022).
  void _openSettings(WidgetRef ref) =>
      ref.read(activeOverlayProvider.notifier).state = ShellOverlay.settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(tabsControllerProvider.notifier);
    final overlay = ref.watch(activeOverlayProvider);

    final bindings = <ShortcutActivator, VoidCallback>{
      // Close active tab.
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
          _closeActive(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
          _closeActive(context, ref),

      // Per-terminal zoom.
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
          _zoomActive(ref, (t) => t.zoomIn()),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
          _zoomActive(ref, (t) => t.zoomIn()),
      const SingleActivator(LogicalKeyboardKey.add, meta: true): () =>
          _zoomActive(ref, (t) => t.zoomIn()),
      const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
          _zoomActive(ref, (t) => t.zoomIn()),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
          _zoomActive(ref, (t) => t.zoomOut()),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          _zoomActive(ref, (t) => t.zoomOut()),
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () =>
          _zoomActive(ref, (t) => t.zoomReset()),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
          _zoomActive(ref, (t) => t.zoomReset()),

      // MRU cycling (Ctrl+Tab / Ctrl+Shift+Tab).
      const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
          n.cycleMru(true),
      const SingleActivator(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      ): () =>
          n.cycleMru(false),

      // Next / previous tab in the active group.
      const SingleActivator(
        LogicalKeyboardKey.bracketRight,
        meta: true,
        shift: true,
      ): () =>
          n.activateRelativeInActiveGroup(1),
      const SingleActivator(
        LogicalKeyboardKey.bracketRight,
        control: true,
        shift: true,
      ): () =>
          n.activateRelativeInActiveGroup(1),
      const SingleActivator(
        LogicalKeyboardKey.bracketLeft,
        meta: true,
        shift: true,
      ): () =>
          n.activateRelativeInActiveGroup(-1),
      const SingleActivator(
        LogicalKeyboardKey.bracketLeft,
        control: true,
        shift: true,
      ): () =>
          n.activateRelativeInActiveGroup(-1),

      // Split active group right.
      const SingleActivator(LogicalKeyboardKey.backslash, meta: true): () =>
          n.splitRight(),
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): () =>
          n.splitRight(),

      // Merge / unsplit the current split (ADR 0036 D6). Shift distinguishes it
      // from the plain split binding above.
      const SingleActivator(
        LogicalKeyboardKey.backslash,
        meta: true,
        shift: true,
      ): () =>
          n.unsplit(),
      const SingleActivator(
        LogicalKeyboardKey.backslash,
        control: true,
        shift: true,
      ): () =>
          n.unsplit(),

      // New tab → the new-session launcher (home/welcome). ⌘T is free; the
      // shift variant (⌘⇧T) stays bound to reopen below (ADR 0036 D1).
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
          _newTab(ref),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
          _newTab(ref),

      // Reopen the last closed tab.
      const SingleActivator(
        LogicalKeyboardKey.keyT,
        meta: true,
        shift: true,
      ): () =>
          n.reopenClosed(),
      const SingleActivator(
        LogicalKeyboardKey.keyT,
        control: true,
        shift: true,
      ): () =>
          n.reopenClosed(),

      // Toggle the connection sidebar (ADR 0021).
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
          _toggleSidebar(ref),
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
          _toggleSidebar(ref),

      // Open the Settings overlay (ADR 0022).
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
          _openSettings(ref),
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
          _openSettings(ref),

      // Esc closes an open overlay. Bound ONLY while an overlay is open so a
      // terminal's Esc is never intercepted (ADR 0022). The overlay also binds
      // Esc within its own subtree; this global binding guarantees it works
      // regardless of where focus currently sits.
      if (overlay != ShellOverlay.none)
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(activeOverlayProvider.notifier).state = ShellOverlay.none,
    };

    // Cmd/Ctrl+1..4 → activate a rail destination (ADR 0030 D7). These take the
    // low digits; editor-group focus moves to 5..9 (split layouts beyond four
    // panels are rare, and the destinations are the primary navigation).
    const destDigits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    for (var i = 0; i < destDigits.length; i++) {
      final dest = ShellDestination.values[i];
      bindings[SingleActivator(destDigits[i], meta: true)] = () =>
          activateDestination(dest, ref);
      bindings[SingleActivator(destDigits[i], control: true)] = () =>
          activateDestination(dest, ref);
    }

    // Cmd/Ctrl+5..9 → focus editor group by index (digit5 → first group). The
    // low digits are reserved for rail destinations, so group focus starts at 5.
    const groupDigits = [
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < groupDigits.length; i++) {
      bindings[SingleActivator(groupDigits[i], meta: true)] = () =>
          n.focusGroupByIndex(i);
      bindings[SingleActivator(groupDigits[i], control: true)] = () =>
          n.focusGroupByIndex(i);
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}
