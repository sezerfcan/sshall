import 'package:flutter/material.dart';
import '../../services/sftp/transfer_plan.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';

/// Asked ONCE before a recursive folder transfer: how to handle files that
/// already exist at the destination. Avoids a per-file dialog storm for trees
/// with many files (spec §2 / §6). Returns null if the user cancels.
Future<OverwritePolicy?> showOverwritePolicyDialog(
    BuildContext context, String folderName) {
  final c = context.c;
  return showDialog<OverwritePolicy>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('"$folderName" klasörünü aktar',
          style: ctx.ui(size: 15, weight: FontWeight.w600)),
      content: Text(
        'Hedefte aynı adlı dosyalar olabilir. Tüm aktarım için bir kural seç.',
        style: ctx.ui(size: 13, color: c.textMuted),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal')),
        Tooltip(
          message: 'Hedefte zaten olan dosyalara dokunma',
          child: TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, OverwritePolicy.skipExisting),
              child: const Text('Mevcutları atla')),
        ),
        Tooltip(
          message: 'Her çakışmada ayrı ayrı sor',
          child: TextButton(
              onPressed: () => Navigator.pop(ctx, OverwritePolicy.askEach),
              child: const Text('Her birini sor')),
        ),
        PrimaryButton(
            label: 'Üzerine yaz',
            onPressed: () => Navigator.pop(ctx, OverwritePolicy.overwrite)),
      ],
    ),
  );
}
