import 'package:flutter/material.dart';
import '../../theme/context_ext.dart';

class ComingSoonView extends StatelessWidget {
  final String title;
  final IconData icon;
  const ComingSoonView({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: c.textDim),
        const SizedBox(height: 14),
        Text(title, style: context.ui(size: 16, weight: FontWeight.w600, color: c.textMuted)),
        const SizedBox(height: 6),
        Text('Faz 4\'te geliyor', style: context.ui(size: 13, color: c.textDim)),
      ]),
    );
  }
}
