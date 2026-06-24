import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';

enum OverwriteChoice { overwrite, keepBoth, skip }

/// Returns [name] if free, else inserts ` (n)` before the extension until
/// [exists] reports the candidate is free.
String uniqueName(String name, bool Function(String) exists) {
  if (!exists(name)) return name;
  final ext = p.extension(name);
  final stem = name.substring(0, name.length - ext.length);
  var n = 1;
  while (true) {
    final candidate = '$stem ($n)$ext';
    if (!exists(candidate)) return candidate;
    n++;
  }
}

Future<OverwriteChoice?> showOverwriteDialog(
    BuildContext context, String name) {
  final c = context.c;
  return showDialog<OverwriteChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('"$name" zaten var',
          style: ctx.ui(size: 15, weight: FontWeight.w600)),
      content: Text(
        'Hedefte aynı adlı bir öğe var. Ne yapmak istersin?',
        style: ctx.ui(size: 13, color: c.textMuted),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, OverwriteChoice.skip),
            child: const Text('Atla')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, OverwriteChoice.keepBoth),
            child: const Text('İki kopya')),
        PrimaryButton(
            label: 'Üzerine yaz',
            onPressed: () => Navigator.pop(ctx, OverwriteChoice.overwrite)),
      ],
    ),
  );
}
