import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/folders/connection_ops.dart';
import '../../data/models/connection.dart';
import '../../data/models/identity.dart';
import '../../data/models/vault_data.dart';
import '../../data/secure_store/secure_store.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_label.dart';
import '../shell/shell_overlay.dart';
import '../shell/shell_state.dart';
import 'generate_key_dialog.dart';
import 'identity_actions.dart';
import 'identity_detail.dart';
import 'identity_filter.dart';
import 'identity_row.dart';
import 'identity_view_model.dart';
import 'known_hosts_actions.dart';
import 'known_hosts_section.dart';
import 'vault_search_bar.dart';

/// Interactive vault: header + stats + searchable identity manager + known-hosts
/// (ADR 0033). No secret material is ever rendered (ADR 0005) — only the
/// NON-SECRET public key + fingerprint via [IdentityView].
class VaultView extends ConsumerWidget {
  const VaultView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(secureStoreProvider);
    return storeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (store) => ListenableBuilder(
        listenable: store.revision,
        builder: (context, _) => _VaultBody(store: store, ref: ref),
      ),
    );
  }
}

class _VaultBody extends StatefulWidget {
  final SecureStore store;
  final WidgetRef ref;
  const _VaultBody({required this.store, required this.ref});

  @override
  State<_VaultBody> createState() => _VaultBodyState();
}

class _VaultBodyState extends State<_VaultBody> {
  final _search = TextEditingController();
  final _hostSearch = TextEditingController();
  String _query = '';
  String _hostQuery = '';
  IdentityTypeFilter _typeFilter = IdentityTypeFilter.all;
  bool _unusedOnly = false;

  SecureStore get _store => widget.store;

  @override
  void dispose() {
    _search.dispose();
    _hostSearch.dispose();
    super.dispose();
  }

  IdentityView _viewOf(Identity id) => IdentityView.of(id);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final data = _store.snapshot().valueOrNull ?? VaultData.empty();
    final identities = data.identities;
    final pins = data.pins;

    final keyCount = identities
        .where((i) => i.type == IdentityType.privateKey)
        .length;

    final usage = {
      for (final id in identities) id.id: identityUsage(data, id.id),
    };
    final filtered = filterIdentities(
      identities,
      query: _query,
      typeFilter: _typeFilter,
      unusedOnly: _unusedOnly,
      usage: usage,
      viewOf: _viewOf,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Vault — Anahtar & Kimlik',
                      style: context.ui(size: 22, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yerel şifreli depo · ADR 0005',
                      style: context.ui(size: 13, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message:
                    'Yeni bir SSH anahtarı üret; vault’a kaydedilir, public key’i sunucuna eklersin.',
                child: PrimaryButton(
                  key: const Key('generateKey'),
                  label: 'Yeni anahtar üret',
                  icon: Icons.add,
                  onPressed: () => showGenerateKeyDialog(context, widget.ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _StatRow(keyCount: keyCount, knownHosts: pins.length),
          const SizedBox(height: 28),

          // ── Identity manager ────────────────────────────────────────────
          const SectionLabel('Kimlikler'),
          const SizedBox(height: 12),
          VaultSearchBar(
            controller: _search,
            typeFilter: _typeFilter,
            unusedOnly: _unusedOnly,
            onQueryChanged: (v) => setState(() => _query = v),
            onTypeChanged: (f) => setState(() => _typeFilter = f),
            onUnusedChanged: (v) => setState(() => _unusedOnly = v),
          ),
          const SizedBox(height: 14),
          if (identities.isEmpty)
            _EmptyIdentities()
          else if (filtered.isEmpty)
            _EmptyMatch()
          else
            for (final id in filtered) ...[
              IdentityRow(
                key: Key('identityRow-${id.id}'),
                view: _viewOf(id),
                usage: usage[id.id] ?? 0,
                onOpen: () => _openDetail(id),
                onAction: (a) => _handleRowAction(id, a),
              ),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 28),

          // ── Known hosts ─────────────────────────────────────────────────
          _HostSearch(
            controller: _hostSearch,
            onChanged: (v) => setState(() => _hostQuery = v),
          ),
          const SizedBox(height: 12),
          KnownHostsSection(
            pins: pins,
            query: _hostQuery,
            onRevoke: (pin) => revokePinFlow(context, _store, pin),
          ),
        ],
      ),
    );
  }

  // ── Action wiring ──────────────────────────────────────────────────────

  Future<void> _handleRowAction(Identity id, IdentityRowAction action) async {
    final view = _viewOf(id);
    switch (action) {
      case IdentityRowAction.copyPublicKey:
        if (view.publicKeyOpenSSH != null) {
          await copyPublicKeyFlow(context, view.publicKeyOpenSSH!);
        }
      case IdentityRowAction.copyFingerprint:
        if (view.fingerprint != null) {
          await copyFingerprintFlow(context, view.fingerprint!);
        }
      case IdentityRowAction.rename:
        await renameIdentityFlow(context, _store, id);
      case IdentityRowAction.export:
        if (view.publicKeyOpenSSH != null) {
          await exportPublicKeyFlow(context, id, view.publicKeyOpenSSH!);
        }
      case IdentityRowAction.delete:
        await _delete(id);
    }
  }

  Future<void> _delete(Identity id) async {
    final data = _store.snapshot().valueOrNull ?? VaultData.empty();
    await deleteIdentityFlow(
      context,
      _store,
      id,
      usage: identityUsage(data, id.id),
    );
  }

  void _openDetail(Identity id) {
    final data = _store.snapshot().valueOrNull ?? VaultData.empty();
    final view = _viewOf(id);
    final refs = referencing(data, id.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.c.elevated,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: IdentityDetail(
              view: view,
              usage: identityUsage(data, id.id),
              referencingConnections: refs.connections,
              onRename: () async {
                Navigator.pop(ctx);
                await renameIdentityFlow(context, _store, id);
              },
              onDelete: () async {
                Navigator.pop(ctx);
                await _delete(id);
              },
              onExport: view.publicKeyOpenSSH == null
                  ? null
                  : () => exportPublicKeyFlow(
                      context,
                      id,
                      view.publicKeyOpenSSH!,
                    ),
              onCopyPublicKey: view.publicKeyOpenSSH == null
                  ? null
                  : () => copyPublicKeyFlow(context, view.publicKeyOpenSSH!),
              onCopyFingerprint: view.fingerprint == null
                  ? null
                  : () => copyFingerprintFlow(context, view.fingerprint!),
              onJumpToConnection: (conn) {
                Navigator.pop(ctx);
                _jumpToConnection(conn);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Navigate from a vault identity's "Kullanan bağlantılar" row to that
  /// connection's home/detail: close the Vault overlay and bring the connection
  /// home forward with [conn] selected (the same path the sidebar uses —
  /// app_shell `onSelect`). The connection is carried whole by the callback, so
  /// no id→Connection resolution is needed.
  void _jumpToConnection(Connection conn) {
    final ref = widget.ref;
    ref.read(activeOverlayProvider.notifier).state = ShellOverlay.none;
    ref.read(selectedConnectionProvider.notifier).state = conn;
    ref.read(homeRequestedProvider.notifier).state = true;
  }
}

class _HostSearch extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _HostSearch({required this.controller, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: 'Bilinen hostları host adına göre ara',
      child: TextField(
        key: const Key('hostSearch'),
        controller: controller,
        onChanged: onChanged,
        cursorColor: c.accent,
        style: context.ui(size: 14),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 16, color: c.textDim),
          hintText: 'Host ara',
          hintStyle: context.ui(size: 14, color: c.textDim),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: c.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final int keyCount;
  final int knownHosts;
  const _StatRow({required this.keyCount, required this.knownHosts});

  static const double _minCardWidth = 150;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatCard(
        label: 'SSH Anahtarı',
        value: '$keyCount',
        icon: Icons.vpn_key_outlined,
      ),
      _StatCard(
        label: 'Bilinen Host',
        value: '$knownHosts',
        icon: Icons.verified_outlined,
      ),
      const _StatCard(
        label: 'Depo Durumu',
        value: 'Açık',
        icon: Icons.lock_open_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsInRow =
            constraints.maxWidth >=
            _minCardWidth * cards.length + _gap * (cards.length - 1);
        if (fitsInRow) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        final perRow = constraints.maxWidth >= _minCardWidth * 2 + _gap ? 2 : 1;
        final cardWidth = (constraints.maxWidth - _gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: c.textDim),
              const SizedBox(width: 6),
              Text(label, style: context.ui(size: 11.5, color: c.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.ui(size: 20, weight: FontWeight.w700, color: c.text),
          ),
        ],
      ),
    );
  }
}

class _EmptyIdentities extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vpn_key_outlined, size: 36, color: c.textDim),
          const SizedBox(height: 12),
          Text(
            'Henüz kayıtlı kimlik yok',
            style: context.ui(
              size: 14,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Kimlikler bağlantı sırasında "Kasaya kaydet" seçeneğiyle eklenir.',
            style: context.ui(size: 12.5, color: c.textDim),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyMatch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.border),
      ),
      child: Center(
        child: Text(
          'Aramayla eşleşen kimlik yok',
          style: context.ui(size: 12.5, color: c.textDim),
        ),
      ),
    );
  }
}
