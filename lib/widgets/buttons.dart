import 'package:flutter/material.dart';
import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'pressable.dart';

/// Shared button radius (== [Radii.md8], the dominant control radius). Drives
/// both the painted decoration and the [Pressable] focus ring / state wash so
/// the ring hugs the button shape.
const BorderRadius _kButtonRadius = BorderRadius.all(
  Radius.circular(Radii.md8),
);

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      borderRadius: _kButtonRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: _kButtonRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: c.bg),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: context
                  .textBody(color: c.bg)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SecondaryButton({super.key, required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      borderRadius: _kButtonRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: _kButtonRadius,
          border: Border.all(color: c.border),
        ),
        child: Text(
          label,
          style: context
              .textBody(color: c.text)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const GhostButton({super.key, required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    semanticLabel: label,
    borderRadius: _kButtonRadius,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Text(
        label,
        style: context
            .textBody(color: context.c.textMuted)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const DangerButton({super.key, required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      borderRadius: _kButtonRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(color: c.red, borderRadius: _kButtonRadius),
        child: Text(
          label,
          style: context
              .textBody(color: c.bg)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 38,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The painted face (Tooltip wraps the visual). Pressable stays OUTERMOST so
    // its >=44px hit target is not gated by the Tooltip wrapper.
    Widget face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: _kButtonRadius,
        border: Border.all(color: c.border),
      ),
      child: Icon(icon, size: IconSizes.sm16, color: c.textMuted),
    );
    if (tooltip != null) face = Tooltip(message: tooltip!, child: face);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: tooltip,
      borderRadius: _kButtonRadius,
      child: face,
    );
  }
}
