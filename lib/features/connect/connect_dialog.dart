import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/folder.dart';
import '../../data/models/identity.dart';
import '../../services/keygen/credential_choice.dart';
import '../../services/ssh/ssh_messages.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/buttons.dart';
import 'widgets/auth_selector.dart';
import 'widgets/connect_validation.dart';
import 'widgets/folder_combobox.dart';
import 'widgets/host_paste_parser.dart';
import 'widgets/tag_input.dart';

/// Optional values to prefill the form with (Quick Connect hands these in).
class ConnectPrefill {
  final String? host;
  final int? port;
  final String? username;
  const ConnectPrefill({this.host, this.port, this.username});
}

/// What the user asked the dialog to do (ADR 0031, D4). Both actions persist
/// the host; only [saveAndConnect] also opens a session.
enum ConnectAction { save, saveAndConnect }

/// The result of accepting the "Add Host" dialog (ADR 0031, D1/D4/D8).
///
/// Always defines a SAVED host (there is no "save?" boolean anymore — D1).
/// [params] carries the resolved connect parameters. The credential is captured
/// two ways, mutually exclusive (D8):
///   - [existingAuthRef] set  → reuse that vault identity, mint NOTHING.
///   - [existingAuthRef] null → a fresh secret lives in [params]
///     (password / imported PEM) and the save path mints a new Identity.
class ConnectDialogResult {
  final ConnectAction action;
  final SshConnectParams params;
  final String label;

  /// Folder the saved host belongs to; null = root.
  final String? folderId;

  /// Host-only tags.
  final List<String> tags;

  /// When non-null, reuse this existing vault identity (do NOT mint — D8).
  final String? existingAuthRef;

  /// Advanced: this host runs Docker.
  final bool docker;

  /// Advanced: docker binary override (e.g. "sudo docker"); null = "docker".
  final String? dockerBinary;

  const ConnectDialogResult({
    required this.action,
    required this.params,
    required this.label,
    this.folderId,
    this.tags = const [],
    this.existingAuthRef,
    this.docker = false,
    this.dockerBinary,
  });

  bool get connect => action == ConnectAction.saveAndConnect;
}

Future<ConnectDialogResult?> showConnectDialog(
  BuildContext context, {
  ConnectPrefill? prefill,
  List<Folder> folders = const [],
  List<Identity> identities = const [],
  String? defaultUsername,
  int? defaultPort,
}) => showDialog<ConnectDialogResult>(
  context: context,
  builder: (_) => _ConnectDialog(
    prefill: prefill,
    folders: folders,
    identities: identities,
    defaultUsername: defaultUsername,
    defaultPort: defaultPort,
  ),
);

class _ConnectDialog extends StatefulWidget {
  final ConnectPrefill? prefill;
  final List<Folder> folders;
  final List<Identity> identities;

  /// Pre-fill defaults read from AppSettings (ADR 0038 D6). The prefill (Quick
  /// Connect) still wins where it supplies a value; these only fill the blanks.
  final String? defaultUsername;
  final int? defaultPort;

  const _ConnectDialog({
    this.prefill,
    this.folders = const [],
    this.identities = const [],
    this.defaultUsername,
    this.defaultPort,
  });

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  final _dockerBinary = TextEditingController();
  late final TagInputController _tags;
  late final AuthSelectionController _auth;

  final _labelFocus = FocusNode();
  final _hostFocus = FocusNode();
  final _portFocus = FocusNode();
  final _userFocus = FocusNode();

  String? _folderId;
  bool _docker = false;
  bool _advancedOpen = false;

  /// Stops Host→Label auto-derive once the user edits Label themselves (D2).
  bool _labelEdited = false;

  /// Per-field errors currently shown (D5). Populated on submit/blur; cleared
  /// live as the user fixes the field.
  ConnectFieldErrors _errors = const ConnectFieldErrors();

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _label = TextEditingController();
    _host = TextEditingController(text: p?.host ?? '');
    // Port default order (ADR 0038 D6): prefill (Quick Connect) > settings
    // default > hard 22. Backward compatible — with no setting it still shows 22.
    _port = TextEditingController(
      text: (p?.port ?? widget.defaultPort ?? 22).toString(),
    );
    // Username default order: prefill > settings default > empty.
    _user = TextEditingController(
      text: (p?.username?.isNotEmpty ?? false)
          ? p!.username!
          : (widget.defaultUsername ?? ''),
    );
    _tags = TagInputController();
    _auth = AuthSelectionController();
    // Derive an initial label from a prefilled host so Quick Connect lands with
    // a sensible name the user can still edit.
    if ((p?.host ?? '').isNotEmpty) _label.text = p!.host!;

    _hostFocus.addListener(() {
      if (!_hostFocus.hasFocus) _revalidateField(ConnectField.host);
    });
    _labelFocus.addListener(() {
      if (!_labelFocus.hasFocus) _revalidateField(ConnectField.label);
    });
    _portFocus.addListener(() {
      if (!_portFocus.hasFocus) _revalidateField(ConnectField.port);
    });
  }

  @override
  void dispose() {
    for (final c in [_label, _host, _port, _user, _dockerBinary]) {
      c.dispose();
    }
    _tags.dispose();
    _auth.dispose();
    for (final f in [_labelFocus, _hostFocus, _portFocus, _userFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  // --- Host paste auto-split + label auto-derive (D7/D2) -------------------

  void _onHostChanged(String value) {
    final parsed = parseHostPaste(value);
    // Only fan out when the paste is structured (carries a user or a port);
    // otherwise leave the raw text in Host so plain typing isn't disrupted.
    if (parsed.isStructured) {
      if (parsed.host != null) _host.text = parsed.host!;
      if (parsed.username != null) _user.text = parsed.username!;
      if (parsed.port != null) _port.text = parsed.port!.toString();
    }
    if (!_labelEdited) {
      _label.text = (parsed.host ?? value).trim();
    }
    _clearIfFixed(ConnectField.host);
    setState(() {});
  }

  void _onLabelChanged(String _) {
    _labelEdited = true;
    _clearIfFixed(ConnectField.label);
  }

  // --- Validation wiring (D5) ----------------------------------------------

  ConnectFieldErrors _computeErrors() => ConnectFieldErrors.validate(
    label: _label.text,
    host: _host.text,
    port: _port.text,
    useKey: _auth.useKey,
    hasExistingIdentity: _auth.hasExistingIdentity,
    hasImportedKey: _auth.hasImportedKey,
    password: _auth.password.text,
  );

  /// Re-runs validation for ONE field on blur, but only adds an error (never
  /// clears another field's existing error from a blur of an unrelated field).
  void _revalidateField(ConnectField field) {
    final fresh = _computeErrors();
    setState(() {
      _errors = ConnectFieldErrors(
        label: field == ConnectField.label ? fresh.label : _errors.label,
        host: field == ConnectField.host ? fresh.host : _errors.host,
        port: field == ConnectField.port ? fresh.port : _errors.port,
        credential: field == ConnectField.credential
            ? fresh.credential
            : _errors.credential,
      );
    });
  }

  /// Live-clears a field's error as soon as it becomes valid (D5).
  void _clearIfFixed(ConnectField field) {
    if (_errors.errorFor(field) == null) return;
    final fresh = _computeErrors();
    if (fresh.errorFor(field) == null) {
      setState(() {
        _errors = ConnectFieldErrors(
          label: field == ConnectField.label ? null : _errors.label,
          host: field == ConnectField.host ? null : _errors.host,
          port: field == ConnectField.port ? null : _errors.port,
          credential: field == ConnectField.credential
              ? null
              : _errors.credential,
        );
      });
    }
  }

  void _onAuthChanged() => _clearIfFixed(ConnectField.credential);

  FocusNode _focusFor(ConnectField f) => switch (f) {
    ConnectField.label => _labelFocus,
    ConnectField.host => _hostFocus,
    ConnectField.port => _portFocus,
    // No dedicated node for the credential block; focus the closest field.
    ConnectField.credential => _userFocus,
  };

  // --- Submit (D4) ---------------------------------------------------------

  void _submit(ConnectAction action) {
    final errors = _computeErrors();
    if (!errors.isValid) {
      setState(() => _errors = errors);
      final first = errors.firstInvalid;
      if (first != null) _focusFor(first).requestFocus();
      return;
    }

    final cred = credentialFrom(
      useKey: _auth.useKey,
      password: _auth.password.text,
      pem: _auth.importedPem,
      keyPassphrase: _auth.keyPassphrase.text,
    );

    // D8: when an existing identity is reused, we pass its ref out and must NOT
    // ship a secret in params (the save path resolves the secret from the
    // identity). Only ship a secret when minting a fresh credential.
    final reuse = _auth.useKey && _auth.hasExistingIdentity;
    final params = SshConnectParams(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _user.text.trim(),
      password: reuse ? null : (cred.isKey ? null : cred.secret),
      privateKeyPem: reuse ? null : (cred.isKey ? cred.secret : null),
      keyPassphrase: reuse ? null : cred.passphrase,
    );

    final bin = _dockerBinary.text.trim();
    Navigator.pop(
      context,
      ConnectDialogResult(
        action: action,
        params: params,
        label: _label.text.trim(),
        folderId: _folderId,
        tags: _tags.tags,
        existingAuthRef: reuse ? _auth.selectedIdentityId : null,
        docker: _docker,
        dockerBinary: _docker && bin.isNotEmpty ? bin : null,
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _SubmitIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _SubmitIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
      },
      child: Actions(
        actions: {
          _SubmitIntent: CallbackAction<_SubmitIntent>(
            // Enter triggers the PRIMARY action: "Bağlan ve kaydet" (D7).
            onInvoke: (_) {
              _submit(ConnectAction.saveAndConnect);
              return null;
            },
          ),
          _CancelIntent: CallbackAction<_CancelIntent>(
            onInvoke: (_) {
              Navigator.pop(context);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            backgroundColor: c.elevated,
            title: Text(
              'Yeni Bağlantı',
              style: context.ui(size: 16, weight: FontWeight.w600),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Label (autofocus, auto-derived from Host until edited).
                      AppTextField(
                        controller: _label,
                        focusNode: _labelFocus,
                        autofocus: true,
                        label: 'Etiket',
                        hintText: 'örn. Prod Web',
                        fieldKey: const Key('label'),
                        errorText: _errors.label,
                        onChanged: _onLabelChanged,
                      ),
                      const SizedBox(height: 12),
                      // Host (wide) + Port (narrow) on one row (D2).
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: AppTextField(
                              controller: _host,
                              focusNode: _hostFocus,
                              label: 'Host',
                              hintText: 'örn. 192.168.1.10',
                              fieldKey: const Key('host'),
                              errorText: _errors.host,
                              onChanged: _onHostChanged,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 96,
                            child: AppTextField(
                              controller: _port,
                              focusNode: _portFocus,
                              label: 'Port',
                              hintText: '22',
                              fieldKey: const Key('port'),
                              keyboardType: TextInputType.number,
                              errorText: _errors.port,
                              onChanged: (_) =>
                                  _clearIfFixed(ConnectField.port),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _user,
                        focusNode: _userFocus,
                        label: 'Kullanıcı adı',
                        hintText: 'örn. root',
                        fieldKey: const Key('username'),
                      ),
                      const SizedBox(height: 16),
                      AuthSelector(
                        controller: _auth,
                        identities: widget.identities,
                        credentialError: _errors.credential,
                        onChanged: _onAuthChanged,
                      ),
                      const SizedBox(height: 20),
                      // Organisation group.
                      _groupLabel(context, 'Organizasyon'),
                      const SizedBox(height: 10),
                      FolderCombobox(
                        value: _folderId,
                        folders: widget.folders,
                        onChanged: (v) => setState(() => _folderId = v),
                      ),
                      const SizedBox(height: 12),
                      TagInput(controller: _tags),
                      const SizedBox(height: 16),
                      _advancedDisclosure(context),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 12,
              top: 4,
            ),
            // A single Row as the only "action" so we can place a spacer
            // between [Vazgeç] and the right-aligned [Kaydet][Bağlan ve kaydet]
            // (AlertDialog's default OverflowBar rejects Spacer/Expanded).
            actions: [
              // The OverflowBar lays its child at intrinsic width, so a Spacer
              // has no bounded width to flex into. Use spaceBetween with a
              // MainAxisSize.min Row for the right-hand group so the layout is
              // intrinsic-width-safe (no overflow) yet still left/right split.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GhostButton(
                    label: 'Vazgeç',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: 'Oturum açmadan host\'u kaydet',
                        child: SecondaryButton(
                          key: const Key('saveOnly'),
                          label: 'Kaydet',
                          onPressed: () => _submit(ConnectAction.save),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Host\'u kaydet ve hemen bağlan',
                        child: PrimaryButton(
                          key: const Key('saveAndConnect'),
                          label: 'Bağlan ve kaydet',
                          onPressed: () =>
                              _submit(ConnectAction.saveAndConnect),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupLabel(BuildContext context, String text) => Text(
    text,
    style: context.ui(
      size: 12.5,
      weight: FontWeight.w700,
      color: context.c.textMuted,
      spacing: 0.3,
    ),
  );

  Widget _advancedDisclosure(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Docker ve diğer ileri ayarlar',
          child: GestureDetector(
            key: const Key('advancedToggle'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Row(
              children: [
                Icon(
                  _advancedOpen ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: c.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Gelişmiş',
                  style: context.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_advancedOpen) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Semantics(
                label: 'Bu host Docker çalıştırıyor',
                toggled: _docker,
                child: GestureDetector(
                  key: const Key('dockerFlag'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _docker = !_docker),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 23,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _docker ? c.accent : c.borderStrong,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Align(
                      alignment: _docker
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 19,
                        height: 19,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('Bu host Docker çalıştırıyor', style: context.ui(size: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Açıksa kenar çubuğunda bu host\'un konteynerleri listelenir.',
            style: context.ui(size: 11.5, color: c.textDim),
          ),
          if (_docker) ...[
            const SizedBox(height: 12),
            AppTextField(
              controller: _dockerBinary,
              label: 'docker komutu (opsiyonel)',
              hintText: 'örn. sudo docker',
              fieldKey: const Key('dockerBinary'),
            ),
            const SizedBox(height: 6),
            Text(
              'Varsayılan "docker"; sudo/özel yol gerekiyorsa değiştirin.',
              style: context.ui(size: 11.5, color: c.textDim),
            ),
          ],
        ],
      ],
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}
