import 'package:flutter/material.dart';
import '../theme/context_ext.dart';

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: context.ui(size: 11, weight: FontWeight.w700, color: context.c.textDim, spacing: 0.8));
}
