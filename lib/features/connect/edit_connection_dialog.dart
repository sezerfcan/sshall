import 'package:flutter/material.dart';

import '../../data/folders/connection_ops.dart';
import '../../data/models/connection.dart';
import '../../data/models/folder.dart';
import '../../data/models/identity.dart';
import '../../data/resolve/connection_resolver.dart';
import '../../services/keygen/pick_private_key.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_toggle.dart';
import '../../widgets/buttons.dart';

/// The outcome of the edit dialog. When [delete] is true, all other fields are
/// ignored and the caller deletes the connection.
class EditConnectionResult {
  final bool delete;
  final String label;
  final String host;
  final String? folderId;
  final List<String> tags;
  final FieldEdit<String> username;
  final FieldEdit<int> port;
  final IdentityEdit identity;

  /// Whether this host runs Docker (drives the sidebar container view).
  final bool docker;

  /// Optional docker binary/invocation override (null = "docker").
  final String? dockerBinary;

  const EditConnectionResult({
    required this.label,
    required this.host,
    required this.folderId,
    required this.tags,
    required this.username,
    required this.port,
    required this.identity,
    this.docker = false,
    this.dockerBinary,
  }) : delete = false;

  const EditConnectionResult.remove()
    : delete = true,
      label = '',
      host = '',
      folderId = null,
      tags = const [],
      username = const Inherit(),
      port = const Inherit(),
      identity = const IdentityKeep(),
      docker = false,
      dockerBinary = null;
}

Future<EditConnectionResult?> showEditConnectionDialog(
  BuildContext context, {
  required Connection connection,
  required Identity? identity,
  required ResolvedConnection resolved,
  List<Folder> folders = const [],
}) => showDialog<EditConnectionResult>(
  context: context,
  builder: (_) => _EditConnectionDialog(
    connection: connection,
    identity: identity,
    resolved: resolved,
    folders: folders,
  ),
);

/// Confirmation prompt shared by the dialog's "Sil" button and the sidebar's
/// delete action.
Future<bool> confirmDeleteConnection(
  BuildContext context,
  String label,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.elevated,
        title: Text(
          'Bağlantıyı sil',
          style: ctx.ui(size: 16, weight: FontWeight.w600),
        ),
        content: Text(
          '"$label" kalıcı olarak silinsin mi? Bu işlem geri alınamaz.',
          style: ctx.ui(size: 13, color: ctx.c.textMuted),
        ),
        actions: [
          GhostButton(
            label: 'Vazgeç',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          PrimaryButton(
            label: 'Evet, sil',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ) ??
    false;

class _EditConnectionDialog extends StatefulWidget {
  final Connection connection;
  final Identity? identity;
  final ResolvedConnection resolved;
  final List<Folder> folders;
  const _EditConnectionDialog({
    required this.connection,
    required this.identity,
    required this.resolved,
    required this.folders,
  });

  @override
  State<_EditConnectionDialog> createState() => _EditConnectionDialogState();
}

class _EditConnectionDialogState extends State<_EditConnectionDialog> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _user;
  late final TextEditingController _port;
  late final TextEditingController _tags;
  final _password = TextEditingController();
  final _keyPass = TextEditingController();
  late final TextEditingController _dockerBin;

  late bool _userInherit;
  late bool _portInherit;
  late bool _idInherit;
  late bool _useKey;
  late bool _docker;
  String? _folderId;
  String? _pem;
  String? _pemName;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _label = TextEditingController(text: c.label);
    _host = TextEditingController(text: c.host);
    _tags = TextEditingController(text: c.tags.join(', '));
    _folderId = c.folderId;

    _userInherit = c.username == null;
    _user = TextEditingController(
      text: c.username ?? widget.resolved.username ?? '',
    );
    _portInherit = c.port == null;
    _port = TextEditingController(
      text: (c.port ?? widget.resolved.port).toString(),
    );

    _idInherit = c.authRef == null;
    _useKey = widget.identity?.type == IdentityType.privateKey;

    _docker = c.docker;
    _dockerBin = TextEditingController(text: c.dockerBinary ?? '');
  }

  @override
  void dispose() {
    for (final t in [
      _label,
      _host,
      _user,
      _port,
      _tags,
      _password,
      _keyPass,
      _dockerBin,
    ]) {
      t.dispose();
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

  List<String> _parseTags() => _tags.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  void _save() {
    final label = _label.text.trim();
    final host = _host.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Etiket boş olamaz.');
      return;
    }
    if (host.isEmpty) {
      setState(() => _error = 'Host boş olamaz.');
      return;
    }

    final FieldEdit<String> username;
    if (_userInherit) {
      username = const Inherit();
    } else {
      final u = _user.text.trim();
      if (u.isEmpty) {
        setState(
          () =>
              _error = 'Kullanıcı adı boş olamaz (ya da klasörden miras alın).',
        );
        return;
      }
      username = SetValue(u);
    }

    final FieldEdit<int> port;
    if (_portInherit) {
      port = const Inherit();
    } else {
      final p = int.tryParse(_port.text.trim());
      if (p == null || p < 1 || p > 65535) {
        setState(() => _error = 'Port 1–65535 arası bir sayı olmalı.');
        return;
      }
      port = SetValue(p);
    }

    final IdentityEdit identity;
    if (_idInherit) {
      identity = const IdentityInherit();
    } else if (_useKey) {
      if (_pem != null) {
        identity = IdentitySetKey(
          _pem!,
          _keyPass.text.isEmpty ? null : _keyPass.text,
        );
      } else if (widget.identity?.type == IdentityType.privateKey) {
        identity = const IdentityKeep();
      } else {
        setState(() => _error = 'Bir özel anahtar seçin.');
        return;
      }
    } else {
      if (_password.text.isNotEmpty) {
        identity = IdentitySetPassword(_password.text);
      } else if (widget.identity?.type == IdentityType.password) {
        identity = const IdentityKeep();
      } else {
        setState(() => _error = 'Parola girin.');
        return;
      }
    }

    Navigator.pop(
      context,
      EditConnectionResult(
        label: label,
        host: host,
        folderId: _folderId,
        tags: _parseTags(),
        username: username,
        port: port,
        identity: identity,
        docker: _docker,
        dockerBinary: _docker && _dockerBin.text.trim().isNotEmpty
            ? _dockerBin.text.trim()
            : null,
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDeleteConnection(context, widget.connection.label);
    if (!ok || !mounted) return;
    Navigator.pop(context, const EditConnectionResult.remove());
  }

  Widget _helper(String text) =>
      Text(text, style: context.ui(size: 11.5, color: context.c.textDim));

  Widget _inheritRow(String key, bool value, ValueChanged<bool> onChanged) =>
      AppToggle(
        key: Key(key),
        value: value,
        label: 'Klasörden miras al',
        showLabel: true,
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text(
        'Bağlantıyı Düzenle',
        style: context.ui(size: 16, weight: FontWeight.w600),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _label,
                label: 'Etiket',
                fieldKey: const Key('edit-label'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _host,
                label: 'Host',
                fieldKey: const Key('edit-host'),
              ),
              const SizedBox(height: 6),
              _helper(
                "Host'u değiştirirsen sonraki bağlanışta sunucu anahtarı yeniden doğrulanır.",
              ),
              const SizedBox(height: 16),

              // Folder.
              _folderPicker(context),
              const SizedBox(height: 16),

              // Username (inherit ↔ concrete).
              Text(
                'Kullanıcı adı',
                style: context.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              _inheritRow(
                'edit-user-inherit',
                _userInherit,
                (v) => setState(() => _userInherit = v),
              ),
              const SizedBox(height: 8),
              if (_userInherit)
                _helper('↳ klasörden: ${widget.resolved.username ?? '—'}')
              else
                AppTextField(
                  controller: _user,
                  fieldKey: const Key('edit-user'),
                ),
              const SizedBox(height: 16),

              // Port (inherit ↔ concrete).
              Text(
                'Port',
                style: context.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              _inheritRow(
                'edit-port-inherit',
                _portInherit,
                (v) => setState(() => _portInherit = v),
              ),
              const SizedBox(height: 8),
              if (_portInherit)
                _helper('↳ klasörden: ${widget.resolved.port}')
              else
                AppTextField(
                  controller: _port,
                  fieldKey: const Key('edit-port'),
                  keyboardType: TextInputType.number,
                ),
              const SizedBox(height: 16),

              // Identity (inherit ↔ concrete password/key).
              Text(
                'Kimlik',
                style: context.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              _inheritRow(
                'edit-id-inherit',
                _idInherit,
                (v) => setState(() => _idInherit = v),
              ),
              if (!_idInherit) ...[
                const SizedBox(height: 8),
                AppToggle(
                  key: const Key('edit-useKey'),
                  value: _useKey,
                  label: 'Özel anahtar kullan',
                  showLabel: true,
                  onChanged: (v) => setState(() => _useKey = v),
                ),
                const SizedBox(height: 12),
                if (!_useKey)
                  AppTextField(
                    controller: _password,
                    label: 'Parola',
                    obscure: true,
                    fieldKey: const Key('edit-password'),
                    hintText: 'değiştirmek için yeni parola gir',
                  )
                else ...[
                  Row(
                    children: [
                      GhostButton(
                        label: 'Anahtar dosyası içe aktar',
                        onPressed: _pickKey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pemName ?? 'değiştirmek için yeni anahtar seç',
                          style: context.ui(size: 13, color: c.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _keyPass,
                    label: 'Anahtar parolası (opsiyonel)',
                    obscure: true,
                  ),
                ],
              ] else ...[
                const SizedBox(height: 8),
                _helper('↳ klasörden: ${_inheritedIdLabel()}'),
              ],

              const SizedBox(height: 16),
              AppTextField(
                controller: _tags,
                label: 'Etiketler',
                fieldKey: const Key('edit-tags'),
              ),
              const SizedBox(height: 6),
              _helper('Virgülle ayırın (örn. prod, db)'),

              const SizedBox(height: 16),
              // Docker capability (drives the sidebar container view).
              Text(
                'Docker',
                style: context.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                key: const Key('edit-docker'),
                value: _docker,
                onChanged: (v) => setState(() => _docker = v),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Bu sunucu Docker çalıştırıyor',
                  style: context.ui(size: 13),
                ),
                subtitle: _helper(
                  "Açıksa kenar çubuğunda container'ları gösterir.",
                ),
              ),
              if (_docker) ...[
                const SizedBox(height: 8),
                AppTextField(
                  controller: _dockerBin,
                  label: 'docker komutu (opsiyonel)',
                  hintText: 'docker',
                  fieldKey: const Key('edit-docker-bin'),
                ),
                const SizedBox(height: 6),
                _helper('Örn. "sudo docker" veya rootless yol. Boş = docker.'),
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
        GhostButton(label: 'Vazgeç', onPressed: () => Navigator.pop(context)),
        GhostButton(label: 'Sil', onPressed: _delete),
        PrimaryButton(label: 'Kaydet', onPressed: _save),
      ],
    );
  }

  String _inheritedIdLabel() => switch (widget.resolved.authRef) {
    null => '—',
    _ => 'klasör kimliği',
  };

  Widget _folderPicker(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Klasör',
            style: context.ui(
              size: 12,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ),
        DropdownButton<String?>(
          key: const Key('edit-folder'),
          value: _folderId,
          isExpanded: true,
          dropdownColor: c.elevated,
          style: context.ui(size: 14),
          underline: Container(height: 1, color: c.border),
          onChanged: (v) => setState(() => _folderId = v),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('Kök', style: context.ui(size: 14)),
            ),
            for (final f in widget.folders)
              DropdownMenuItem<String?>(
                value: f.id,
                child: Text(f.name, style: context.ui(size: 14)),
              ),
          ],
        ),
      ],
    );
  }
}
