import 'package:flutter/material.dart';

import '../../../theme/context_ext.dart';
import '../../../widgets/app_text_field.dart';

/// An [AppTextField] for secrets (password / key passphrase) with a reveal
/// (eye) suffix toggle (ADR 0031, D3/D9). Starts obscured; tapping the eye
/// shows the value. Local to the connect feature for now; a shared app-wide
/// reveal primitive is deferred to pass-2 (ADR 0031 scope notes).
class RevealTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Tooltip for the reveal toggle (defaults to a Turkish show/hide hint).
  final String revealTooltip;

  const RevealTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.fieldKey,
    this.onChanged,
    this.onSubmitted,
    this.revealTooltip = 'Göster / gizle',
  });

  @override
  State<RevealTextField> createState() => _RevealTextFieldState();
}

class _RevealTextFieldState extends State<RevealTextField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      hintText: widget.hintText,
      errorText: widget.errorText,
      fieldKey: widget.fieldKey,
      obscure: !_visible,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffixIcon: Semantics(
        button: true,
        label: _visible ? 'Gizle' : 'Göster',
        child: Tooltip(
          message: widget.revealTooltip,
          child: InkWell(
            key: const Key('revealToggle'),
            onTap: () => setState(() => _visible = !_visible),
            child: Icon(
              _visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
