import 'package:flutter/material.dart';

import '../../data/models/host_key_pin.dart';
import '../../data/secure_store/secure_store.dart';
import '../../theme/context_ext.dart';
import 'confirm_dialog.dart';

/// Revokes a pinned host key after a SECURITY-FRAMED confirmation (ADR 0033 /
/// D5). Revoking forgets the pin (the GUI equivalent of `ssh-keygen -R`): the
/// next connection re-triggers trust-on-first-use. The dialog shows the OLD
/// fingerprint for comparison and deliberately offers NO one-click re-pin.
Future<bool> revokePinFlow(
  BuildContext context,
  SecureStore store,
  HostKeyPin pin,
) async {
  final full = 'SHA256:${pin.sha256}';
  return showDestructiveConfirm(
    context,
    title: 'Host anahtarını unut',
    confirmLabel: 'Unut',
    confirmKey: const Key('confirmRevokePin'),
    // Drop the matching pin in a single mutate on the confirm click. Match by
    // value (host+type+sha256) since HostKeyPin has no identity-stable id.
    onConfirm: () => store.mutate(
      (v) => v.copyWith(
        pins: [
          for (final p in v.pins)
            if (!(p.hostPort == pin.hostPort &&
                p.keyType == pin.keyType &&
                p.sha256 == pin.sha256))
              p,
        ],
      ),
    ),
    bodyBuilder: (ctx) {
      final c = ctx.c;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"${pin.hostPort}" için sabitlenmiş anahtar unutulacak.',
            style: ctx.ui(size: 13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            'Bu pini unutursan bir sonraki bağlantıda sunucunun anahtarı '
            'yeniden sorulur (ilk-kullanımda-güven). Sunucu gerçekten '
            'değiştiyse bu doğru; ama bir saldırgan araya girdiyse yeni '
            'anahtarı yanlışlıkla onaylayabilirsin — dikkatli ol.',
            style: ctx.ui(size: 12.5, color: c.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            'Unutulacak parmak izi',
            style: ctx.ui(size: 11, color: c.textDim),
          ),
          const SizedBox(height: 4),
          SelectableText(full, style: ctx.mono(size: 12)),
        ],
      );
    },
  );
}
