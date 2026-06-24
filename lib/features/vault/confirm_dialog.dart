import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';

/// Shared destructive-action confirmation (ADR 0033 / D7).
///
/// Safety contract:
/// - the confirm button is danger-styled ([DangerButton]) and is NOT
///   pre-focused, so an accidental Enter cannot trigger it;
/// - confirmation requires an explicit click (Enter is intercepted and does
///   nothing — only Escape / "Vazgeç" dismisses);
/// - the body states the concrete blast radius the caller passes in
///   ([bodyBuilder]), e.g. the delete reference count or the pin re-trust
///   warning + old fingerprint.
///
/// Returns true on confirm, false on cancel/dismiss.
///
/// When [onConfirm] is supplied it runs (awaited) on the confirm click BEFORE
/// the dialog pops — so a store mutation triggered by the confirmation executes
/// in the same gesture/zone as the tap (important for real-IO tests). The
/// dialog still resolves true.
Future<bool> showDestructiveConfirm(
  BuildContext context, {
  required String title,
  required WidgetBuilder bodyBuilder,
  required String confirmLabel,
  Key? confirmKey,
  Future<void> Function()? onConfirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.c;
      return Shortcuts(
        // Swallow Enter so the destructive action can only fire on an explicit
        // click (D7). Escape still pops via the default dialog barrier handling.
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): DoNothingIntent(),
        },
        child: AlertDialog(
          backgroundColor: c.elevated,
          title: Text(title, style: ctx.ui(size: 16, weight: FontWeight.w600)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(child: bodyBuilder(ctx)),
          ),
          actions: [
            GhostButton(
              label: 'Vazgeç',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            DangerButton(
              key: confirmKey,
              label: confirmLabel,
              onPressed: () async {
                if (onConfirm != null) await onConfirm();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}
