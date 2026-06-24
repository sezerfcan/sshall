import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/context_ext.dart';

/// The full-area in-app overlays that ride on top of the session workspace
/// (ADR 0022). Management surfaces — Settings & Vault — are NOT session tabs;
/// they open here, over the live sessions, and close back to them.
enum ShellOverlay { none, settings, vault }

/// Which overlay (if any) is currently shown over the workspace. Only one at a
/// time; opening another replaces it. Sessions underneath stay live (the
/// workspace IndexedStack keeps them mounted — the overlay only paints on top).
final activeOverlayProvider = StateProvider<ShellOverlay>(
  (ref) => ShellOverlay.none,
);

/// A full-area panel drawn as the top layer of the workspace stack: a header
/// (icon + title + close button) over [child]. It captures **Esc** to close —
/// scoped to this subtree, which is only mounted while an overlay is open, so a
/// terminal's Esc is never intercepted. The whole control is discoverable
/// (tooltip on close, keyboard hint).
class OverlayPanel extends ConsumerWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const OverlayPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    void close() =>
        ref.read(activeOverlayProvider.notifier).state = ShellOverlay.none;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Container(
          // Opaque so the panel reads as a dedicated surface, not a translucent
          // modal; sessions underneath stay mounted (live) but hidden.
          color: c.surface,
          child: Column(
            children: [
              _header(context, close),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, VoidCallback close) {
    final c = context.c;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 14, weight: FontWeight.w700),
            ),
          ),
          Tooltip(
            message: 'Kapat (Esc)',
            child: GestureDetector(
              key: const Key('overlayClose'),
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: Semantics(
                button: true,
                label: 'Paneli kapat',
                child: Container(
                  width: 34,
                  height: 30,
                  alignment: Alignment.center,
                  child: Icon(Icons.close, size: 18, color: c.textMuted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
