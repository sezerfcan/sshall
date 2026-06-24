import 'package:flutter/material.dart';

import '../../../data/models/identity.dart';
import '../../../services/keygen/pick_private_key.dart';
import '../../../theme/context_ext.dart';
import '../../../widgets/buttons.dart';
import 'reveal_text_field.dart';

/// The two authentication methods the connect form offers (ADR 0031, D3). A
/// slot for `agent` is intentionally left for a future pass (ssh-agent is out
/// of scope here) — do NOT add it without the agent backend.
enum AuthMethod { key, password }

/// Holds the live auth-form state so it survives method switches (the old
/// boolean-toggle dialog cleared the other method's controllers on every
/// switch — D3 state-loss bug). The dialog owns one of these for the lifetime
/// of the form; [AuthSelector] mounts BOTH sub-forms (IndexedStack) so their
/// controllers stay alive regardless of which segment is visible.
class AuthSelectionController extends ChangeNotifier {
  AuthMethod method;

  /// Selected existing vault identity id; null = none selected (import / typed
  /// password path). When set AND the key segment is active, the dialog reuses
  /// this identity instead of minting a new one (D8).
  String? selectedIdentityId;

  final TextEditingController password = TextEditingController();
  final TextEditingController keyPassphrase = TextEditingController();

  /// Imported key PEM + display name (null until a file is imported).
  String? importedPem;
  String? importedPemName;

  AuthSelectionController({
    this.method = AuthMethod.password,
    this.selectedIdentityId,
  });

  bool get useKey => method == AuthMethod.key;

  bool get hasExistingIdentity => selectedIdentityId != null;
  bool get hasImportedKey => importedPem != null;

  void setMethod(AuthMethod m) {
    if (m == method) return;
    method = m;
    notifyListeners();
  }

  void selectIdentity(String? id) {
    selectedIdentityId = id;
    notifyListeners();
  }

  void setImportedKey(String pem, String name) {
    importedPem = pem;
    importedPemName = name;
    // Importing a fresh key is a distinct choice from reusing a saved identity;
    // clear the existing-identity selection so we don't ambiguously do both.
    selectedIdentityId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    password.dispose();
    keyPassphrase.dispose();
    super.dispose();
  }
}

/// Segmented `[SSH Anahtarı | Parola]` authentication picker (ADR 0031, D3).
/// State-retaining: both sub-forms stay mounted via [IndexedStack] so switching
/// segments never clears the other method's input. §9: the segments, the
/// identity dropdown and the import button all carry tooltips/helper text.
class AuthSelector extends StatefulWidget {
  final AuthSelectionController controller;

  /// Existing vault identities offered in the key-mode dropdown.
  final List<Identity> identities;

  /// Field-scoped error for the credential rule (D5); shown under the active
  /// sub-form. null = no error.
  final String? credentialError;

  /// Called whenever the auth selection changes so the parent can live-clear a
  /// credential error as the user fixes it (D5).
  final VoidCallback? onChanged;

  const AuthSelector({
    super.key,
    required this.controller,
    this.identities = const [],
    this.credentialError,
    this.onChanged,
  });

  @override
  State<AuthSelector> createState() => _AuthSelectorState();
}

class _AuthSelectorState extends State<AuthSelector> {
  AuthSelectionController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _pickKey() async {
    final key = await pickPrivateKey();
    if (key == null) return;
    _c.setImportedKey(key.pem, key.name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Kimlik doğrulama',
            style: context.ui(
              size: 12,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ),
        _segmented(context),
        const SizedBox(height: 12),
        // Both sub-forms stay mounted; only the active index is shown so the
        // inactive method's controllers (and typed text) survive the switch.
        IndexedStack(
          index: _c.useKey ? 0 : 1,
          sizing: StackFit.loose,
          children: [_keyForm(context), _passwordForm(context)],
        ),
        if (widget.credentialError != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.credentialError!,
            style: context.ui(size: 11, color: c.red),
          ),
        ],
      ],
    );
  }

  Widget _segmented(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          _segment(
            context,
            key: const Key('authSegKey'),
            label: 'SSH Anahtarı',
            tooltip: 'Özel anahtar ile kimlik doğrula',
            selected: _c.useKey,
            onTap: () => _c.setMethod(AuthMethod.key),
          ),
          const SizedBox(width: 3),
          _segment(
            context,
            key: const Key('authSegPassword'),
            label: 'Parola',
            tooltip: 'Parola ile kimlik doğrula',
            selected: !_c.useKey,
            onTap: () => _c.setMethod(AuthMethod.password),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required Key key,
    required String label,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: context.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: selected ? c.bg : c.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyForm(BuildContext context) {
    final c = context.c;
    final knownIds = widget.identities.map((i) => i.id).toSet();
    final selected = _c.selectedIdentityId;
    // Dangling-ref guard mirrors folder_defaults_dialog._identityDropdown: a
    // selected id that no longer exists is surfaced as an explicit item.
    final dangling = selected != null && !knownIds.contains(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // PRIMARY: pick an existing vault identity.
        Text(
          'Vault kimliği',
          style: context.ui(size: 11.5, color: c.textMuted),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: const Key('authIdentity'),
              value: selected,
              isExpanded: true,
              dropdownColor: c.elevated,
              style: context.ui(size: 14),
              hint: Text(
                'kimlik seç (kayıtlı)…',
                style: context.ui(size: 14, color: c.textDim),
              ),
              onChanged: (v) => _c.selectIdentity(v),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'seçilmedi',
                    style: context.ui(size: 14, color: c.textDim),
                  ),
                ),
                if (dangling)
                  DropdownMenuItem<String?>(
                    value: selected,
                    child: Text(
                      '(eksik kimlik — silinmiş)',
                      style: context.ui(size: 14, color: c.red),
                    ),
                  ),
                for (final i in widget.identities)
                  DropdownMenuItem<String?>(
                    value: i.id,
                    child: Text(i.label, style: context.ui(size: 14)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Kayıtlı bir kimlik seçin ya da yeni bir anahtar dosyası alın.',
          style: context.ui(size: 11.5, color: c.textDim),
        ),
        const SizedBox(height: 12),
        // SECONDARY: import a new key file.
        Row(
          children: [
            GhostButton(
              key: const Key('importKey'),
              label: 'Anahtar dosyası içe aktar…',
              onPressed: _pickKey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _c.importedPemName ?? 'Anahtar seçilmedi',
                style: context.ui(size: 13, color: c.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        RevealTextField(
          controller: _c.keyPassphrase,
          fieldKey: const Key('keyPassphrase'),
          label: 'Anahtar parolası (opsiyonel)',
          hintText: 'şifreli anahtarsa girin',
        ),
      ],
    );
  }

  Widget _passwordForm(BuildContext context) {
    return RevealTextField(
      controller: _c.password,
      fieldKey: const Key('password'),
      label: 'Parola',
      hintText: 'sunucu parolanız',
      errorText: null,
      onChanged: (_) => widget.onChanged?.call(),
    );
  }
}
