import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/context_ext.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? label;

  /// Placeholder shown inside the empty field (e.g. "örn. 192.168.1.10").
  final String? hintText;

  /// Inline, field-scoped validation message. When non-null it is drawn in red
  /// directly under the field and the field border turns red, so the user can
  /// tell WHICH field is wrong instead of reading a single error line above the
  /// whole form (UX report Top-3 #3).
  final String? errorText;

  final bool obscure, autofocus, mono;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  /// Optional input filters (e.g. digits-only / length cap) applied as the user
  /// types — used by numeric fields such as the default-port setting.
  final List<TextInputFormatter>? inputFormatters;
  final Key? fieldKey;

  /// Optional external focus node, so callers can drive focus (e.g. validate on
  /// blur, or move focus to the first invalid field on submit — ADR 0031 D5).
  final FocusNode? focusNode;
  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.obscure = false,
    this.autofocus = false,
    this.mono = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.fieldKey,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hasError = errorText != null;
    return MergeSemantics(
      child: Semantics(
        // Make the field's purpose reachable by a screen reader; without this the
        // visible label is just a sibling Text node and may not be associated.
        // MergeSemantics folds the label + the TextField into one node so a
        // screen reader announces "Kullanıcı adı, edit box" instead of a mute box.
        label: label,
        textField: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  label!,
                  style: context.ui(
                    size: 12,
                    weight: FontWeight.w600,
                    color: c.textMuted,
                  ),
                ),
              ),
            TextField(
              key: fieldKey,
              focusNode: focusNode,
              controller: controller,
              obscureText: obscure,
              autofocus: autofocus,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              cursorColor: c.accent,
              style: mono ? context.mono(size: 13) : context.ui(size: 14),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: prefixIcon,
                suffixIcon: suffixIcon,
                hintText: hintText,
                hintStyle: context.ui(size: 14, color: c.textDim),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: c.bg,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: hasError ? c.red : c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    // Aligned to the shared focusRing token (ADR 0040 D6) so the
                    // field, buttons and toggle all draw the same focus color.
                    // focusRing == accent per theme, so this is pixel-stable.
                    color: hasError ? c.red : c.focusRing,
                    width: 2.0,
                  ),
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  errorText!,
                  style: context.ui(size: 11, color: c.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
