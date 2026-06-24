import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/buttons.dart';

/// The exact word the user must type to confirm a destructive vault reset.
/// Compared case-insensitively; Dart's toUpperCase is ASCII here, so the
/// Turkish İ/ı casing pitfall does not apply.
const _confirmPhrase = 'SIFIRLA';

/// Shows the destructive vault-reset confirmation. Returns true only if the
/// user typed [_confirmPhrase] and pressed the reset button; false if they
/// cancelled or dismissed. Pure UI — it performs no deletion itself, so the
/// caller runs SecureStore.reset() and navigates as appropriate.
Future<bool> showResetVaultDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ResetVaultDialog(),
  );
  return ok ?? false;
}

class _ResetVaultDialog extends StatefulWidget {
  const _ResetVaultDialog();
  @override
  State<_ResetVaultDialog> createState() => _ResetVaultDialogState();
}

class _ResetVaultDialogState extends State<_ResetVaultDialog> {
  final _controller = TextEditingController();

  bool get _confirmed =>
      _controller.text.trim().toUpperCase() == _confirmPhrase;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text("Vault'u sıfırla",
          style: context.ui(size: 16, weight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bu işlem TÜM kayıtlı bağlantılarınızı, kimliklerinizi, '
              'klasörlerinizi ve host-key kayıtlarınızı kalıcı olarak siler. '
              'Master passphrase olmadan bu veriler kurtarılamaz; sıfırlama '
              'GERİ ALINAMAZ.',
              style: context.ui(size: 13, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            Text('Onaylamak için "$_confirmPhrase" yazın:',
                style: context.ui(size: 12.5, color: c.textMuted)),
            const SizedBox(height: 8),
            AppTextField(
              fieldKey: const Key('resetConfirmPhrase'),
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        GhostButton(
          label: 'Vazgeç',
          onPressed: () => Navigator.pop(context, false),
        ),
        DangerButton(
          key: const Key('confirmReset'),
          label: "Vault'u sıfırla",
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
        ),
      ],
    );
  }
}
