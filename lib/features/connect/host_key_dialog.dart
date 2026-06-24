import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';

Future<bool> showHostKeyDialog(
  BuildContext context, {
  required String hostPort,
  required String keyType,
  required String sha256,
  required bool mismatch,
  String? oldSha256,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.c;
      return AlertDialog(
        backgroundColor: c.elevated,
        title: Row(
          children: [
            if (mismatch) ...[
              Icon(Icons.warning_amber_rounded, color: c.yellow),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                mismatch ? 'Host anahtarı değişti' : 'Host anahtarını doğrula',
                style: context.ui(size: 16, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mismatch) ...[
              Text(
                'Sunucunun anahtarı sabitlenen anahtarla EŞLEŞMİYOR. Bu bir '
                'ortadaki-adam (MITM) saldırısı olabilir. Yalnızca anahtarın '
                'neden değiştiğini biliyorsanız (örn. sunucu yeniden kuruldu) '
                'devam edin.',
                style: context.ui(size: 13, color: c.red),
              ),
              const SizedBox(height: 8),
            ],
            Text(hostPort, style: context.ui(size: 14)),
            const SizedBox(height: 4),
            if (mismatch && oldSha256 != null) ...[
              // On a mismatch the user must compare the previously trusted key
              // against the newly presented one to make an informed MITM call.
              Text('Sabitlenen (eski):',
                  style: context.ui(size: 12, color: c.textMuted)),
              Text('$keyType  SHA256:$oldSha256',
                  style: context.mono(size: 12, color: c.textMuted)),
              const SizedBox(height: 6),
              Text('Sunucunun sunduğu (yeni):',
                  style: context.ui(size: 12, color: c.red)),
              Text('$keyType  SHA256:$sha256',
                  style: context.mono(size: 12, color: c.red)),
            ] else
              Text('$keyType  SHA256:$sha256', style: context.mono(size: 12)),
          ],
        ),
        actions: [
          GhostButton(
            label: 'Reddet',
            onPressed: () => Navigator.pop(context, false),
          ),
          PrimaryButton(
            label: mismatch ? 'Yine de güven' : 'Güven & sabitle',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    },
  );
  return accepted ?? false;
}
