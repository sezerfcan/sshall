import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/folders/connection_ops.dart';
import '../../data/models/identity.dart';
import '../../data/secure_store/secure_store.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/buttons.dart';
import 'confirm_dialog.dart';
import 'vault_format.dart';

/// Orchestrates the identity CRUD flows (ADR 0033 / D4). Each flow drives a
/// confirmation/prompt and then a SINGLE atomic [SecureStore.mutate]; the store
/// API is unchanged (mutate + copyWith only). The PRIVATE key is never exported
/// or rendered — only the NON-SECRET public key (ADR 0005).

/// Renames the identity: prompts for a new label, then mutates only the label.
/// The mutate runs inside the dialog's Kaydet click so it executes in the same
/// gesture/zone as the tap (mutates only [Identity.label] — D4).
Future<void> renameIdentityFlow(
  BuildContext context,
  SecureStore store,
  Identity identity,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _RenameDialog(store: store, identity: identity),
  );
}

/// Deletes the identity after a danger-styled confirmation that NAMES the
/// reference count, then removes it and nulls every referencing authRef in the
/// SAME mutate (no dangling ids — D4/D7).
Future<bool> deleteIdentityFlow(
  BuildContext context,
  SecureStore store,
  Identity identity, {
  required int usage,
}) async {
  final confirmed = await showDestructiveConfirm(
    context,
    title: 'Kimliği sil',
    confirmLabel: 'Sil',
    confirmKey: const Key('confirmDeleteIdentity'),
    // Run the single atomic mutate on the confirm click (D4) — removing the
    // identity AND nulling every referencing authRef in one transform.
    onConfirm: () => store.mutate((v) => deleteIdentity(v, identity.id)),
    bodyBuilder: (ctx) {
      final c = ctx.c;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"${identity.label}" kimliği silinecek.',
            style: ctx.ui(size: 13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            usage > 0
                ? 'Bu anahtar $usage bağlantı tarafından kullanılıyor; '
                      'silinince o bağlantılar kimliksiz kalır (bağ silinmez, '
                      'sadece bu kimlik kaldırılır).'
                : 'Bu kimliği hiçbir bağlantı kullanmıyor.',
            style: ctx.ui(size: 12.5, color: c.textMuted),
          ),
          const SizedBox(height: 10),
          Text(
            'Bu işlem geri alınamaz.',
            style: ctx.ui(size: 12.5, color: c.red),
          ),
        ],
      );
    },
  );
  // The mutate already ran inside [onConfirm]; just report the decision.
  return confirmed;
}

/// Exports the NON-SECRET public key to "<label>.pub" (reuses the generate
/// dialog's save logic). The PRIVATE key is out of scope (ADR 0005).
Future<void> exportPublicKeyFlow(
  BuildContext context,
  Identity identity,
  String publicKeyOpenSSH,
) async {
  final safeName = _safeFileName(identity.label);
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Genel anahtarı kaydet',
      fileName: '$safeName.pub',
    );
    if (path == null) return; // cancelled
    await File(path).writeAsString('$publicKeyOpenSSH\n');
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Genel anahtar kaydedildi')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Dosya kaydedilemedi')));
    }
  }
}

/// Sanitizes a label into a safe ".pub" file stem.
String _safeFileName(String label) {
  final cleaned = label.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return cleaned.isEmpty ? 'public_key' : cleaned;
}

class _RenameDialog extends StatefulWidget {
  final SecureStore store;
  final Identity identity;
  const _RenameDialog({required this.store, required this.identity});
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.identity.label,
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final newLabel = _controller.text.trim();
    if (newLabel.isEmpty || newLabel == widget.identity.label) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    await widget.store.mutate(
      (v) => renameIdentity(v, widget.identity.id, newLabel),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text(
        'Yeniden adlandır',
        style: context.ui(size: 16, weight: FontWeight.w600),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: AppTextField(
          fieldKey: const Key('renameIdentityField'),
          controller: _controller,
          label: 'Etiket',
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        GhostButton(label: 'Vazgeç', onPressed: () => Navigator.pop(context)),
        PrimaryButton(
          key: const Key('renameIdentityConfirm'),
          label: 'Kaydet',
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Copies the public key with feedback (D4/D8).
Future<void> copyPublicKeyFlow(BuildContext context, String publicKey) =>
    copyWithFeedback(context, publicKey, label: 'Genel anahtar');

/// Copies the fingerprint with feedback (D4/D8).
Future<void> copyFingerprintFlow(BuildContext context, String fingerprint) =>
    copyWithFeedback(context, fingerprint, label: 'Parmak izi');
