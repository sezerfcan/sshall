import 'package:flutter/material.dart';
import '../theme/context_ext.dart';

class StatusPill extends StatelessWidget {
  final String label; final bool connected;
  const StatusPill({super.key, required this.label, required this.connected});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = connected ? c.green : c.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: connected ? c.green.withValues(alpha: .14) : c.surface2, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: context.ui(size: 11, weight: FontWeight.w600, color: col)),
      ]),
    );
  }
}
