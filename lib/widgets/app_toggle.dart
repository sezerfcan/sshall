import 'package:flutter/material.dart';
import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'pressable.dart';

/// A switch control. When [label] is given it renders the label as PART of the
/// control: the whole row (label + track) is ONE focusable, ≥44px-tall hit
/// target that toggles on tap, Enter and Space (ADR 0040 D5) — so callers no
/// longer pair the toggle with a separate, untappable sibling `Text`.
///
/// The 40×23 track paint is preserved (knob 19×19, accent/borderStrong, radius
/// 12); only the knob color is tokenized (`onAccent` instead of a raw
/// `Colors.white`) and a keyboard focus ring + hover/pressed states are added on
/// top via the shared [Pressable] primitive — all additive, so the at-rest
/// appearance is unchanged.
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Accessible name for the switch (e.g. "Vault'a kaydet"). Always exposed to
  /// screen readers together with the on/off state. When [showLabel] is true it
  /// is ALSO rendered as a tappable visible label beside the track.
  final String? label;

  /// Render [label] as a visible, tappable label that is part of the control
  /// (the whole row toggles). Callers whose surrounding row template already
  /// shows the label/description (e.g. settings) keep this false so the label is
  /// not duplicated; dialogs that used to pair the toggle with a sibling `Text`
  /// set it true so that sibling collapses into the control.
  final bool showLabel;

  const AppToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 40,
      height: 23,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? c.accent : c.borderStrong,
        borderRadius: BorderRadius.circular(Radii.lg12),
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 19,
          height: 19,
          decoration: BoxDecoration(color: c.onAccent, shape: BoxShape.circle),
        ),
      ),
    );

    final hasLabel = showLabel && label != null && label!.isNotEmpty;
    final Widget content = hasLabel
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              track,
              const Gap.h(Spacing.sm8 + 2), // 10px — the legacy label gap.
              Flexible(child: Text(label!, style: context.textBody())),
            ],
          )
        : track;

    // Pressable owns the accessible node (switch + label + on/off + tap/focus),
    // and — crucially — its enlarged ≥44px [_HitTarget] render object is the
    // OUTERMOST object, so nothing above it gates the overflow hits. The screen
    // reader reads "<label>, switch, on/off".
    return Pressable(
      onPressed: () => onChanged(!value),
      isToggle: true,
      toggledState: value,
      semanticLabel: label,
      // The ring/wash hug a pill matching the control's rounded feel.
      borderRadius: BorderRadius.circular(Radii.lg12),
      child: content,
    );
  }
}
