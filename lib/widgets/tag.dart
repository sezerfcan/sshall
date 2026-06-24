import 'package:flutter/material.dart';
import '../theme/context_ext.dart';

enum TagVariant { neutral, warning, danger }

class Tag extends StatelessWidget {
  final String text; final TagVariant variant; final bool mono;
  const Tag({super.key, required this.text, this.variant = TagVariant.neutral, this.mono = true});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (fg, bg, border) = switch (variant) {
      TagVariant.neutral => (c.textMuted, c.surface2, c.border),
      TagVariant.warning => (c.yellow, c.yellow.withValues(alpha: .14), Colors.transparent),
      TagVariant.danger => (c.red, c.red.withValues(alpha: .14), Colors.transparent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5), border: Border.all(color: border)),
      child: Text(text, style: (mono ? context.mono(size: 10.5) : context.ui(size: 10.5)).copyWith(fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
