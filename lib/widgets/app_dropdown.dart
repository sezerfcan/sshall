import 'package:flutter/material.dart';
import '../theme/context_ext.dart';

/// A compact dropdown aligned with the app's token system (ADR 0009). Used for
/// settings like the terminal font family and the open-on-launch choice
/// (ADR 0038 D5/D7). [labelOf] renders each option's display text so callers can
/// map enums/strings to Turkish labels. Carries a [semanticLabel].
class AppDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;
  final Key? buttonKey;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.semanticLabel,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: semanticLabel,
      value: labelOf(value),
      child: Container(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: buttonKey,
            value: value,
            isDense: true,
            // Not isExpanded: the dropdown can sit in an unbounded-width slot
            // (the right side of a settings row), so it sizes to its content.
            isExpanded: false,
            borderRadius: BorderRadius.circular(8),
            dropdownColor: c.elevated,
            icon: Icon(Icons.expand_more, size: 18, color: c.textMuted),
            style: context.ui(size: 13, color: c.text),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: [
              for (final item in items)
                DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelOf(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.ui(size: 13, color: c.text),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
