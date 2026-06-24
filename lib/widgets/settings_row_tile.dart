import 'package:flutter/material.dart';
import '../theme/context_ext.dart';

/// The consistent settings-row template (ADR 0038 D3/D11): a leading label +
/// one-line helper on the left, the right-aligned [control]. Every setting row
/// thus carries a label AND a short description. Layout only —
/// the control is provided by the caller (AppToggle / AppTextField / stepper /
/// dropdown), so the same template renders every kind of setting.
class SettingsRowTile extends StatelessWidget {
  final String label;
  final String description;
  final Widget control;

  /// When true, the control is laid out BELOW the label/description on its own
  /// row (wide controls like a text field). Default: control sits on the right.
  final bool stackControl;

  const SettingsRowTile({
    super.key,
    required this.label,
    required this.description,
    required this.control,
    this.stackControl = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.ui(size: 13.5, weight: FontWeight.w600, color: c.text),
        ),
        const SizedBox(height: 2),
        Text(description, style: context.ui(size: 12, color: c.textMuted)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: stackControl
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 8), control],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                control,
              ],
            ),
    );
  }
}
