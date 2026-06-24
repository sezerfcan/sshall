import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../vault/reset_vault_dialog.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/buttons.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  const UnlockScreen({super.key, required this.onUnlocked});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  bool _exists = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Guard re-entry: the button is disabled while busy, but onSubmitted (Enter)
    // is not, so a fast double-Enter could otherwise fire create()/unlock()
    // concurrently against the vault.
    if (_busy) return;
    // When creating a new vault, the passphrase is the only thing standing
    // between the user and a permanently unlockable vault. Require a matching
    // confirmation before we ever persist it (UX report Top-3 #3).
    if (!_exists && _controller.text != _confirmController.text) {
      setState(() => _error = 'Parolalar eşleşmiyor');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Result<void> r;
    try {
      final store = await ref.read(secureStoreProvider.future);
      final pass = _controller.text;
      r = _exists ? await store.unlock(pass) : await store.create(pass);
    } catch (_) {
      // Defense in depth: the store methods return typed failures, but a
      // provider/IO error must never leave the button stuck disabled.
      r = const Err(StorageFailure('Unexpected error'));
    }
    if (!mounted) return;
    if (r.isOk) {
      widget.onUnlocked();
    } else {
      setState(() {
        _busy = false;
        _error = r.failureOrNull?.message;
      });
    }
  }

  Future<void> _reset() async {
    final confirmed = await showResetVaultDialog(context);
    if (!confirmed || !mounted) return;
    try {
      final store = await ref.read(secureStoreProvider.future);
      await store.reset();
    } catch (_) {
      // reset() returns a typed Result and does not throw; this only guards a
      // provider/IO error so the screen never gets stuck.
    }
    if (!mounted) return;
    // Rebuild: the FutureBuilder re-runs vaultExists() (now false) and the
    // screen switches to "Vault Oluştur".
    setState(() {
      _controller.clear();
      _confirmController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(secureStoreProvider);
    return Scaffold(
      body: Center(
        child: storeAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Storage error: $e'),
          data: (store) {
            return FutureBuilder<bool>(
              future: store.vaultExists(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const CircularProgressIndicator();
                }
                _exists = snap.data!;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: context.c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.c.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 32, color: context.c.accent),
                          const SizedBox(height: 14),
                          Text(
                            _exists ? "Vault'u Aç" : 'Vault Oluştur',
                            textAlign: TextAlign.center,
                            style: context.ui(
                                size: 20, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 18),
                          AppTextField(
                            fieldKey: const Key('passphrase'),
                            controller: _controller,
                            label: 'Ana parola',
                            obscure: _obscure,
                            autofocus: true,
                            onSubmitted: (_) => _submit(),
                            suffixIcon: IconButton(
                              key: const Key('passphraseVisibility'),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                                color: context.c.textMuted,
                              ),
                              tooltip: _obscure
                                  ? 'Parolayı göster'
                                  : 'Parolayı gizle',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          if (!_exists) ...[
                            const SizedBox(height: 12),
                            AppTextField(
                              fieldKey: const Key('passphraseConfirm'),
                              controller: _confirmController,
                              label: 'Parolayı tekrar girin',
                              obscure: _obscure,
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Bu parola kayıtlı bağlantı ve anahtarlarınızı '
                              'şifreler. Unutursanız geri alınamaz.',
                              style: context.ui(
                                  size: 11, color: context.c.textDim),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!,
                                style: context.ui(
                                    size: 12, color: context.c.red)),
                          ],
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: _exists ? 'Aç' : 'Oluştur',
                            icon: Icons.lock_open_outlined,
                            onPressed: _busy ? null : _submit,
                          ),
                          if (_exists) ...[
                            const SizedBox(height: 14),
                            Tooltip(
                              message:
                                  'Master passphrase\'inizi unuttuysanız vault\'u '
                                  'sıfırlayıp sıfırdan başlayabilirsiniz. Kayıtlı '
                                  'tüm bağlantı ve kimlikler silinir; bu işlem '
                                  'geri alınamaz.',
                              child: GestureDetector(
                                key: const Key('forgotPassphrase'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _busy ? null : _reset,
                                child: Text(
                                  'Şifremi unuttum — vault\'u sıfırla',
                                  textAlign: TextAlign.center,
                                  style: context.ui(
                                      size: 12, color: context.c.textMuted),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
