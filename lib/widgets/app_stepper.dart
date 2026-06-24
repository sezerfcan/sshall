import 'package:flutter/material.dart';
import '../theme/context_ext.dart';

/// A compact integer stepper (− value +) aligned with [AppToggle]/[AppTextField]
/// styling (ADR 0009 tokens only). Used for settings like the terminal font
/// size and the default port (ADR 0038 D5/D6). The buttons disable at the
/// [min]/[max] bounds so the value can never leave the valid range. Each button
/// carries a tooltip.
class AppStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  /// Optional unit suffix shown after the number (e.g. "sn"). Null = none.
  final String? unit;

  /// Accessible name for the whole control (screen readers).
  final String? semanticLabel;

  const AppStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.unit,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final canDec = value > min;
    final canInc = value < max;
    return Semantics(
      label: semanticLabel,
      value: '$value${unit == null ? '' : ' $unit'}',
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: Icons.remove,
              tooltip: 'Azalt',
              enabled: canDec,
              buttonKey: const Key('stepperDec'),
              onTap: () => onChanged((value - step).clamp(min, max)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: Text(
                unit == null ? '$value' : '$value $unit',
                textAlign: TextAlign.center,
                style: context.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: c.text,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              tooltip: 'Artır',
              enabled: canInc,
              buttonKey: const Key('stepperInc'),
              onTap: () => onChanged((value + step).clamp(min, max)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final Key? buttonKey;

  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 16, color: c.textMuted),
          ),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: btn);
  }
}
