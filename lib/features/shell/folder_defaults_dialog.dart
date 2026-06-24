import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/folders/folder_ops.dart';
import '../../data/models/folder.dart';
import '../../data/models/identity.dart';
import '../../services/keygen/credential_choice.dart';
import '../../services/keygen/pick_private_key.dart';
import '../../theme/app_colors.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_toggle.dart';
import '../../widgets/buttons.dart';

/// Opens the folder-defaults editor. Lets the user set inheritable
/// username/port/identity for [folderId]; empty fields inherit from the parent.
/// Identity can be picked from the existing list or created inline
/// (password / imported key — not keygen).
Future<void> showFolderDefaultsDialog(
  BuildContext context,
  WidgetRef ref, {
  required String folderId,
}) async {
  final store = await ref.read(secureStoreProvider.future);
  final data = store.snapshot().valueOrNull;
  if (data == null) return;
  final matches = data.folders.where((f) => f.id == folderId);
  if (matches.isEmpty) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _FolderDefaultsDialog(folder: matches.first, ref: ref),
  );
}

class _FolderDefaultsDialog extends StatefulWidget {
  final Folder folder;
  final WidgetRef ref;
  const _FolderDefaultsDialog({required this.folder, required this.ref});

  @override
  State<_FolderDefaultsDialog> createState() => _FolderDefaultsDialogState();
}

class _FolderDefaultsDialogState extends State<_FolderDefaultsDialog> {
  late final TextEditingController _user;
  late final TextEditingController _port;
  final _idLabel = TextEditingController();
  final _password = TextEditingController();
  final _keyPass = TextEditingController();

  /// Currently selected existing identity id; null = inherit / none.
  String? _selectedIdentity;
  bool _newIdentity = false;
  bool _useKey = false;
  String? _pem;
  String? _pemName;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.folder;
    _user = TextEditingController(text: f.username ?? '');
    _port = TextEditingController(text: f.port?.toString() ?? '');
    _selectedIdentity = f.authRef;
  }

  @override
  void dispose() {
    for (final c in [_user, _port, _idLabel, _password, _keyPass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickKey() async {
    final key = await pickPrivateKey();
    if (key == null) return;
    setState(() {
      _pem = key.pem;
      _pemName = key.name;
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    // Validate the port before touching the store. Blank = inherit (intended),
    // but a non-numeric / out-of-range value must surface an error rather than
    // silently clearing the folder's configured port.
    final portText = _port.text.trim();
    int? p;
    if (portText.isNotEmpty) {
      p = int.tryParse(portText);
      if (p == null || p < 1 || p > 65535) {
        setState(
          () => _error =
              'Port 1–65535 arası bir sayı olmalı (miras için boş bırakın).',
        );
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final store = await widget.ref.read(secureStoreProvider.future);
      final u = _user.text.trim();

      Identity? newIdentity;
      String? authRef = _selectedIdentity;
      if (_newIdentity) {
        final newId = 'id-${DateTime.now().microsecondsSinceEpoch}';
        final label = _idLabel.text.trim();
        final cred = credentialFrom(
          useKey: _useKey,
          password: _password.text,
          pem: _pem,
          keyPassphrase: _keyPass.text,
        );
        newIdentity = Identity(
          id: newId,
          label: label.isEmpty ? 'kimlik' : label,
          type: cred.identityType,
          secret: cred.secretOrEmpty,
          passphrase: cred.passphrase,
        );
        authRef = newId;
      }

      // Single atomic mutate: append the new identity (if any) AND set the
      // folder defaults in one persist, so an interruption between two writes
      // can't orphan an identity that no folder references.
      final created = newIdentity;
      final result = await store.mutate((v) {
        final base = created == null
            ? v
            : v.copyWith(identities: [...v.identities, created]);
        return setFolderDefaults(
          base,
          widget.folder.id,
          username: u.isEmpty ? null : u,
          port: p,
          authRef: authRef,
        );
      });

      if (!mounted) return;
      if (result.isOk) {
        Navigator.pop(context);
      } else {
        setState(() {
          _saving = false;
          _error =
              'Kaydedilemedi: ${result.failureOrNull?.message ?? 'bilinmeyen hata'}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Beklenmeyen hata oluştu.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = widget.ref.watch(secureStoreProvider).valueOrNull;
    final identities =
        store?.snapshot().valueOrNull?.identities ?? const <Identity>[];

    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text(
        'Klasör varsayılanları — ${widget.folder.name}',
        style: context.ui(size: 16, weight: FontWeight.w600),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Boş bıraktığınız alanlar üst klasörden miras alınır.',
                style: context.ui(size: 12.5, color: c.textMuted),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _user,
                label: 'Username',
                fieldKey: const Key('folderUsername'),
              ),
              const SizedBox(height: 4),
              Text(
                'üst klasörden miras almak için boş bırakın',
                style: context.ui(size: 11, color: c.textDim),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _port,
                label: 'Port',
                fieldKey: const Key('folderPort'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 4),
              Text(
                'üst klasörden miras almak için boş bırakın',
                style: context.ui(size: 11, color: c.textDim),
              ),
              const SizedBox(height: 16),
              Text(
                'Kimlik',
                style: context.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              _identityDropdown(identities, c),
              const SizedBox(height: 4),
              Text(
                'boş bırakırsanız üst klasörden miras alınır',
                style: context.ui(size: 11, color: c.textDim),
              ),
              const SizedBox(height: 12),
              AppToggle(
                key: const Key('newIdentity'),
                value: _newIdentity,
                label: 'Yeni kimlik',
                showLabel: true,
                onChanged: (v) => setState(() => _newIdentity = v),
              ),
              if (_newIdentity) ...[
                const SizedBox(height: 12),
                AppTextField(controller: _idLabel, label: 'Kimlik etiketi'),
                const SizedBox(height: 12),
                AppToggle(
                  value: _useKey,
                  label: 'Özel anahtar kullan',
                  showLabel: true,
                  onChanged: (v) => setState(() => _useKey = v),
                ),
                const SizedBox(height: 12),
                if (!_useKey)
                  AppTextField(
                    controller: _password,
                    label: 'Password',
                    obscure: true,
                  ),
                if (_useKey) ...[
                  Row(
                    children: [
                      GhostButton(
                        label: 'Import key file',
                        onPressed: _pickKey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pemName ?? 'No key selected',
                          style: context.ui(size: 13, color: c.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _keyPass,
                    label: 'Key passphrase (optional)',
                    obscure: true,
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: context.ui(size: 12, color: c.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Vazgeç',
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        PrimaryButton(
          key: const Key('saveFolderDefaults'),
          label: 'Kaydet',
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _identityDropdown(List<Identity> identities, AppColors c) {
    final knownIds = identities.map((i) => i.id).toSet();
    // A folder may still reference an identity that was later deleted.
    // DropdownButton asserts value matches exactly one item, so surface the
    // dangling ref as an explicit item instead of crashing the dialog.
    final dangling =
        _selectedIdentity != null && !knownIds.contains(_selectedIdentity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const Key('folderIdentity'),
          value: _selectedIdentity,
          isExpanded: true,
          dropdownColor: c.elevated,
          style: context.ui(size: 14),
          hint: Text('miras / yok', style: context.ui(size: 14)),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('miras / yok', style: context.ui(size: 14)),
            ),
            if (dangling)
              DropdownMenuItem<String?>(
                value: _selectedIdentity,
                child: Text(
                  '(eksik kimlik — silinmiş)',
                  style: context.ui(size: 14, color: c.red),
                ),
              ),
            for (final i in identities)
              DropdownMenuItem<String?>(
                value: i.id,
                child: Text(i.label, style: context.ui(size: 14)),
              ),
          ],
          onChanged: (v) => setState(() => _selectedIdentity = v),
        ),
      ),
    );
  }
}
