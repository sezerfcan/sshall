import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/models/identity.dart';
import '../../services/keygen/key_generator.dart';
import '../../theme/app_colors.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/buttons.dart';

/// Opens the "generate SSH key" flow: configure → generate (off-isolate) →
/// save to vault as an Identity → show fingerprint + copyable public key.
/// The private key is never shown (ADR 0005); it lives only in the vault.
Future<void> showGenerateKeyDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => _GenerateKeyDialog(ref: ref),
  );
}

class _GenerateKeyDialog extends StatefulWidget {
  final WidgetRef ref;
  const _GenerateKeyDialog({required this.ref});
  @override
  State<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends State<_GenerateKeyDialog> {
  final _label = TextEditingController();
  final _comment = TextEditingController();
  KeyAlgorithm _algorithm = KeyAlgorithm.ed25519;
  EcdsaCurve _curve = EcdsaCurve.p256;
  int _rsaBits = 4096;
  bool _busy = false;
  String? _error;
  GeneratedKey? _result;

  @override
  void dispose() {
    _label.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final label = _label.text.trim().isEmpty
          ? 'üretilen anahtar'
          : _label.text.trim();
      final comment = _comment.text.trim().isEmpty
          ? '$label@sshall'
          : _comment.text.trim();

      final generated = await widget.ref
          .read(keyGeneratorProvider)
          .generate(
            algorithm: _algorithm,
            curve: _curve,
            rsaBits: _rsaBits,
            comment: comment,
          );

      // Persist BEFORE showing the result so closing the dialog never loses
      // the key. Single atomic mutate appends the new Identity.
      final store = await widget.ref.read(secureStoreProvider.future);
      // Persist the NON-SECRET public key + fingerprint at generation (ADR 0033
      // / D1) instead of discarding them — so the vault never has to re-derive
      // them from the PEM on read. The private key stays in `secret` only.
      final identity = Identity(
        id: 'id-${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        type: IdentityType.privateKey,
        secret: generated.privateKeyPem,
        passphrase: null,
        publicKeyOpenSSH: generated.publicKeyOpenSSH,
        fingerprint: generated.fingerprint,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final res = await store.mutate(
        (v) => v.copyWith(identities: [...v.identities, identity]),
      );
      if (!mounted) return;
      if (res.isOk) {
        setState(() {
          _busy = false;
          _result = generated;
        });
      } else {
        setState(() {
          _busy = false;
          _error =
              'Kaydedilemedi: ${res.failureOrNull?.message ?? 'bilinmeyen hata'}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Anahtar üretilemedi.';
        });
      }
    }
  }

  Future<void> _copyPublicKey() async {
    await Clipboard.setData(ClipboardData(text: _result!.publicKeyOpenSSH));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Public key panoya kopyalandı')),
      );
    }
  }

  Future<void> _savePub() async {
    final ext = switch (_result!.algorithm) {
      KeyAlgorithm.ed25519 => 'ed25519',
      KeyAlgorithm.ecdsa => 'ecdsa',
      KeyAlgorithm.rsa => 'rsa',
    };
    try {
      // On desktop, saveFile() only returns the chosen path (the native panel
      // grants write access to it); it does NOT write the file — we write it.
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Public key kaydet',
        fileName: 'id_$ext.pub',
      );
      if (path == null) return; // user cancelled
      await File(path).writeAsString('${_result!.publicKeyOpenSSH}\n');
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Public key kaydedildi')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Dosya kaydedilemedi')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text(
        _result == null ? 'Yeni SSH anahtarı üret' : 'Anahtar üretildi',
        style: context.ui(size: 16, weight: FontWeight.w600),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: _result == null ? _form(c) : _resultView(c),
        ),
      ),
      actions: _result == null
          ? [
              GhostButton(
                label: 'Vazgeç',
                onPressed: _busy ? null : () => Navigator.pop(context),
              ),
              PrimaryButton(
                key: const Key('generateKeyConfirm'),
                label: _busy ? 'Üretiliyor…' : 'Üret',
                onPressed: _busy ? null : _generate,
              ),
            ]
          : [
              PrimaryButton(
                label: 'Bitti',
                onPressed: () => Navigator.pop(context),
              ),
            ],
    );
  }

  Widget _form(AppColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'SSH anahtarı = parolasız, daha güvenli giriş. Üret → public key’i sunucuna ekle.',
        style: context.ui(size: 12.5, color: c.textMuted),
      ),
      const SizedBox(height: 16),
      AppTextField(controller: _label, label: 'Etiket (opsiyonel)'),
      const SizedBox(height: 4),
      Text(
        'Bu anahtarı vault’ta tanıman için isim',
        style: context.ui(size: 11, color: c.textDim),
      ),
      const SizedBox(height: 16),
      Text(
        'Algoritma',
        style: context.ui(
          size: 12,
          weight: FontWeight.w600,
          color: c.textMuted,
        ),
      ),
      const SizedBox(height: 6),
      _algorithmDropdown(c),
      if (_algorithm == KeyAlgorithm.ecdsa) ...[
        const SizedBox(height: 12),
        _curveDropdown(c),
      ],
      if (_algorithm == KeyAlgorithm.rsa) ...[
        const SizedBox(height: 12),
        _rsaDropdown(c),
      ],
      const SizedBox(height: 16),
      AppTextField(controller: _comment, label: 'Comment (opsiyonel)'),
      const SizedBox(height: 4),
      Text(
        'Sunucuda anahtarı tanımana yarar (boşsa <etiket>@sshall)',
        style: context.ui(size: 11, color: c.textDim),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: context.ui(size: 12, color: c.red)),
      ],
    ],
  );

  Widget _resultView(AppColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Anahtar üretildi ve vault’a kaydedildi.',
        style: context.ui(size: 12.5, color: c.textMuted),
      ),
      const SizedBox(height: 12),
      Text('Fingerprint', style: context.ui(size: 11, color: c.textDim)),
      Text(_result!.fingerprint, style: context.mono(size: 12)),
      const SizedBox(height: 12),
      Text(
        'Public key (sunucuya ekle)',
        style: context.ui(size: 11, color: c.textDim),
      ),
      const SizedBox(height: 4),
      SelectableText(_result!.publicKeyOpenSSH, style: context.mono(size: 12)),
      const SizedBox(height: 12),
      // Wrap (not Row) so the two action buttons flow to a second line on
      // narrow widths instead of overflowing the 460px dialog constraint.
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PrimaryButton(
            key: const Key('copyPublicKey'),
            label: 'Public key’i kopyala',
            onPressed: _copyPublicKey,
          ),
          SecondaryButton(label: '.pub kaydet', onPressed: _savePub),
        ],
      ),
    ],
  );

  Widget _algorithmDropdown(AppColors c) => _dropdown<KeyAlgorithm>(
    key: const Key('algorithm'),
    value: _algorithm,
    items: const {
      KeyAlgorithm.ed25519: 'Ed25519 (önerilen)',
      KeyAlgorithm.ecdsa: 'ECDSA',
      KeyAlgorithm.rsa: 'RSA',
    },
    onChanged: (v) => setState(() => _algorithm = v),
    c: c,
  );

  Widget _curveDropdown(AppColors c) => _dropdown<EcdsaCurve>(
    value: _curve,
    items: const {
      EcdsaCurve.p256: 'P-256',
      EcdsaCurve.p384: 'P-384',
      EcdsaCurve.p521: 'P-521',
    },
    onChanged: (v) => setState(() => _curve = v),
    c: c,
  );

  Widget _rsaDropdown(AppColors c) => _dropdown<int>(
    value: _rsaBits,
    items: const {4096: '4096 bit', 2048: '2048 bit'},
    onChanged: (v) => setState(() => _rsaBits = v),
    c: c,
  );

  Widget _dropdown<T>({
    Key? key,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
    required AppColors c,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: c.bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.border),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: key,
        value: value,
        isExpanded: true,
        dropdownColor: c.elevated,
        style: context.ui(size: 14),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(
              value: e.key,
              child: Text(e.value, style: context.ui(size: 14)),
            ),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    ),
  );
}
