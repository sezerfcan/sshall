import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/models/connection.dart';
import '../../data/models/folder.dart';
import '../../data/models/identity.dart';
import '../../data/folders/folder_ops.dart';
import '../../data/resolve/connection_params.dart';
import '../../data/resolve/connection_resolver.dart';
import '../../data/secure_store/secure_store.dart';
import '../../services/sftp/sftp_service.dart';
import '../../services/ssh/ssh_messages.dart';
import '../../services/ssh/ssh_service.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import '../../widgets/host_card.dart';
import '../../widgets/section_label.dart';
import '../../widgets/tag.dart';
import '../connect/connect_dialog.dart';
import '../settings/app_settings.dart';
import '../connect/host_key_dialog.dart';
import '../connect/widgets/host_paste_parser.dart';
import '../shell/connection_actions.dart';
import '../shell/shell_state.dart';
import '../sftp/sftp_providers.dart';
import 'host_detail_card.dart';
import 'host_key_policy.dart';
import 'host_status_provider.dart';
import 'quick_connect_bar.dart';
import 'quick_connect_router.dart';
import 'recent_targets_controller.dart';

/// Connection manager view. Header + QuickConnectBar + "Son Bağlananlar" grid
/// + "Seçili Host" detail card. Owns the connect orchestration (carried over
/// from the old HomeScreen), adapted to drive the desktop shell via providers
/// instead of Navigator.push.
class ConnectionsView extends ConsumerStatefulWidget {
  const ConnectionsView({super.key});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView> {
  // ---------------------------------------------------------------------------
  // Connect orchestration (carried over from HomeScreen, adapted for the shell).
  // ---------------------------------------------------------------------------

  // SFTP event subscriptions for the *current* SFTP session. Kept so they are
  // cancelled when a new session is opened (or this view is disposed); without
  // this, every SFTP open/re-open leaked two StreamSubscriptions and the closed
  // session's broadcast controllers never drained. Mirrors the disciplined
  // `sub.cancel()` of the terminal connect path.
  StreamSubscription? _sftpHostKeySub;
  StreamSubscription? _sftpErrorSub;

  Future<void> _cancelSftpSubs() async {
    await _sftpHostKeySub?.cancel();
    await _sftpErrorSub?.cancel();
    _sftpHostKeySub = null;
    _sftpErrorSub = null;
  }

  @override
  void dispose() {
    // Fire-and-forget: cancel() returns a Future but dispose() is sync; the
    // subscriptions are torn down regardless and we drop our references.
    unawaited(_cancelSftpSubs());
    super.dispose();
  }

  Future<void> _openConnect({ConnectPrefill? prefill}) async {
    final store = await ref.read(secureStoreProvider.future);
    final data = store.snapshot().valueOrNull;
    final folders = data?.folders ?? const <Folder>[];
    final identities = data?.identities ?? const <Identity>[];
    if (!mounted) return;
    // Connection defaults flow from AppSettings into the dialog (ADR 0038 D6):
    // username + port pre-fill the blank fields (backward compatible — no
    // setting still yields port 22).
    final settings = ref.read(appSettingsControllerProvider);
    final res = await showConnectDialog(
      context,
      prefill: prefill,
      folders: folders,
      identities: identities,
      defaultUsername: settings.defaultUsername.isEmpty
          ? null
          : settings.defaultUsername,
      defaultPort: settings.defaultPort,
    );
    if (res == null) return;

    // ADR 0031 D4 (critical data-loss fix): persist on dialog ACCEPT, not on a
    // successful connect. A failed/auth-rejected connect no longer discards the
    // host the user just entered, and offline/draft hosts can be saved. The old
    // code only ran _persistConnection inside the StatusEvent.ready listener.
    await _persistConnection(
      store,
      res.params,
      res.label,
      folderId: res.folderId,
      tags: res.tags,
      existingAuthRef: res.existingAuthRef,
      docker: res.docker,
      dockerBinary: res.dockerBinary,
    );

    // Only "Bağlan ve kaydet" opens a session; "Kaydet" persists silently.
    if (res.connect) {
      await _connect(res.params, label: res.label);
    }
  }

  /// Shared host-key trust decision used by BOTH the terminal connect path and
  /// the SFTP open path. Evaluates the presented key against stored pins via
  /// [HostKeyPolicy]/[HostKeyCoordinator], prompts the user on first-use or
  /// mismatch, and persists the pin only on first-use or an accepted-mismatch
  /// (a plain match is already pinned identically, so re-writing would
  /// needlessly re-encrypt the vault and rebuild the UI on every reconnect to a
  /// known host). Returns the accept/reject decision to hand to the session.
  Future<bool> _decideHostKey(
    SshConnectParams params, {
    required String keyType,
    required String sha256,
  }) async {
    final store = await ref.read(secureStoreProvider.future);
    final policy = HostKeyPolicy(ref.read(hostKeyCoordinatorProvider));
    final hostPort = '${params.host}:${params.port}';

    final pins = store.snapshot().valueOrNull?.pins ?? const [];
    final d = policy.decide(
      hostPort: hostPort,
      keyType: keyType,
      sha256: sha256,
      pins: pins,
    );
    var accept = d.autoAccept ?? false;
    if (d.autoAccept == null && mounted) {
      // On a mismatch, surface the previously pinned fingerprint so the user can
      // compare old vs new and make an informed MITM decision instead of blindly
      // trusting a silently-replaced key.
      String? oldSha256;
      if (d.mismatch) {
        for (final pin in pins) {
          if (pin.hostPort == hostPort && pin.keyType == keyType) {
            oldSha256 = pin.sha256;
            break;
          }
        }
      }
      accept = await showHostKeyDialog(
        context,
        hostPort: hostPort,
        keyType: keyType,
        sha256: sha256,
        mismatch: d.mismatch,
        oldSha256: oldSha256,
      );
    }
    if (accept && d.autoAccept != true) {
      await store.mutate(
        (v) => v.copyWith(
          pins: [
            // Scope pin replacement by (hostPort, keyType) so an ed25519
            // pin doesn't wipe an existing rsa pin for the same host.
            ...v.pins.where(
              (x) => !(x.hostPort == hostPort && x.keyType == keyType),
            ),
            ref
                .read(hostKeyCoordinatorProvider)
                .pinFor(hostPort: hostPort, keyType: keyType, sha256: sha256),
          ],
        ),
      );
    }
    return accept;
  }

  /// Opens a live SSH session and drives a terminal tab. Persistence is NO
  /// longer this method's job (ADR 0031 D4): the host is already saved on
  /// dialog accept, so a failed connect here can't lose data. Used by both the
  /// "Bağlan ve kaydet" path and the saved-host connect/reopen paths.
  ///
  /// ADR 0032 D2/D3: the terminal tab is opened IMMEDIATELY (in `connecting`),
  /// not on `ready`, so the in-pane connecting overlay and the persistent error
  /// card surface every phase. The host-key dialog still runs while the pane
  /// shows "connecting" (D2) — its subscription is set up before the session is
  /// handed off. When [existingTabId] is set the connect is a manual reconnect:
  /// the new session is rebound onto the SAME controller/tab (scrollback
  /// preserved) instead of opening a new tab (D5). [conn] enables the error
  /// card's `[Bağlantıyı Düzenle]` action.
  Future<void> _connect(
    SshConnectParams p, {
    String? label,
    Connection? conn,
    String? existingTabId,
  }) async {
    final ssh = ref.read(sshServiceProvider);
    final hostPort = '${p.host}:${p.port}';

    final SshSession session;
    try {
      session = await ssh.connect(p);
    } catch (_) {
      // Isolate spawn / handshake failure (rare, app-level) — there is no pane
      // to host an error card here, so a transient notice is the last resort.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bağlantı başlatılamadı')));
      }
      return;
    }

    // Host-key verification runs over the live event stream (broadcast) while
    // the pane shows "connecting" — the controller ignores HostKeyRequestEvent,
    // so this dedicated subscription drives the dialog and responds. Cancelled
    // once the session resolves (ready/error/closed) so it never leaks.
    late final StreamSubscription sub;
    sub = session.events.listen((e) async {
      if (e is HostKeyRequestEvent) {
        final accept = await _decideHostKey(
          p,
          keyType: e.keyType,
          sha256: e.sha256,
        );
        session.decideHostKey(accept);
      } else if (e is StatusEvent && e.status == SshStatus.ready) {
        await sub.cancel();
      } else if (e is ErrorEvent || e is ClosedEvent) {
        await sub.cancel();
      }
    });

    final notifier = ref.read(tabsControllerProvider.notifier);
    final editAction = conn == null
        ? null
        : () => editConnectionFlow(context, ref, conn);

    if (existingTabId != null) {
      // Manual reconnect: reuse the same controller/terminal (scrollback kept).
      final ctrl = notifier.controllerFor(existingTabId);
      if (ctrl == null) {
        // The tab is gone — fall back to a fresh tab so the session isn't lost.
        unawaited(session.close());
        return;
      }
      await ctrl.rebind(session);
    } else {
      final title = label ?? hostPort;
      final id = notifier.openTerminal(
        session,
        title,
        hostPort: hostPort,
        onEdit: editAction,
        // Reopen (Cmd/Ctrl+Shift+T) replays the FULL connect flow — a new
        // session + host-key verification — so reopening a terminal stays
        // secure rather than reusing a stale/insecure handle (ADR 0018).
        reopen: () {
          if (mounted) unawaited(_connect(p, label: label, conn: conn));
        },
      );
      // Manual reconnect re-runs connect INTO this same tab (D5). Wired after
      // openTerminal returns the id the thunk needs.
      notifier.controllerFor(id)?.bindReconnect(() async {
        if (mounted) {
          await _connect(p, label: label, conn: conn, existingTabId: id);
        }
      });
    }
    // A session is now front-and-center; leave the home/welcome surface (0022).
    ref.read(homeRequestedProvider.notifier).state = false;
  }

  /// Persists a new saved host. ADR 0031 D8: when [existingAuthRef] is provided
  /// the user reused an existing vault identity — point [Connection.authRef] at
  /// it and DO NOT mint a new Identity. Otherwise mint a fresh Identity from the
  /// secret carried in [p]. One atomic mutate so an interruption can't orphan an
  /// identity no connection references. Called exactly once per dialog accept.
  Future<void> _persistConnection(
    SecureStore store,
    SshConnectParams p,
    String label, {
    String? folderId,
    List<String> tags = const [],
    String? existingAuthRef,
    bool docker = false,
    String? dockerBinary,
  }) async {
    final connId = 'c-${DateTime.now().microsecondsSinceEpoch}';
    final reuse = existingAuthRef != null;
    final idId = reuse
        ? existingAuthRef
        : 'id-${DateTime.now().microsecondsSinceEpoch}';
    await store.mutate(
      (v) => v.copyWith(
        connections: [
          ...v.connections,
          Connection(
            id: connId,
            label: label,
            host: p.host,
            folderId: folderId,
            username: p.username,
            port: p.port,
            authRef: idId,
            tags: tags,
            // Append to the end of this folder's siblings (ADR 0035 D1): the old
            // fixed `order: 0` made every new host collide and fall back to the
            // alphabetical tie-break, so reorder was meaningless.
            order: nextOrder(
              v.connections
                  .where((cn) => cn.folderId == folderId)
                  .map((cn) => cn.order),
            ),
            docker: docker,
            dockerBinary: dockerBinary,
          ),
        ],
        // Only mint a new Identity for a freshly entered secret; reusing an
        // existing one must not duplicate it (D8).
        identities: reuse
            ? v.identities
            : [
                ...v.identities,
                Identity(
                  id: idId,
                  label: label,
                  type: p.privateKeyPem != null
                      ? IdentityType.privateKey
                      : IdentityType.password,
                  secret: p.privateKeyPem ?? p.password ?? '',
                  passphrase: p.keyPassphrase,
                ),
              ],
      ),
    );
  }

  SshConnectParams? _paramsFor(SecureStore store, Connection c) {
    final data = store.snapshot().valueOrNull;
    return paramsFor(
      c,
      folders: data?.folders ?? const <Folder>[],
      identities: data?.identities ?? const <Identity>[],
    );
  }

  // ---------------------------------------------------------------------------
  // Quick Connect routing (ADR 0034 D2/D5). Ephemeral by DEFAULT — the bar
  // NEVER auto-persists. A saved-host match connects reusing its stored identity
  // WITHOUT _persistConnection; anything else falls back to the prefilled dialog
  // (where saving is opt-in via [Kaydet]/[Bağlan ve kaydet]).
  // ---------------------------------------------------------------------------

  /// The `user@host:port` string a recents entry / suggestion stores for a saved
  /// connection (resolved against the folder chain; no secret).
  String _targetFor(SecureStore store, Connection c) {
    final data = store.snapshot().valueOrNull;
    final r = resolve(c, data?.folders ?? const <Folder>[]);
    final user = r.username;
    final at = (user == null || user.isEmpty) ? '' : '$user@';
    return '$at${c.host}:${r.port}';
  }

  String _resolvedHost(Connection c) => c.host;

  int _resolvedPort(SecureStore store, Connection c) {
    final data = store.snapshot().valueOrNull;
    return resolve(c, data?.folders ?? const <Folder>[]).port;
  }

  /// Parses [target], routes it, and connects. Ephemeral-saved → [_connect] with
  /// NO persistence; otherwise → the prefilled dialog fallback. On a successful
  /// ephemeral connect the target string is recorded in recents (no secret).
  Future<void> _quickConnect(SecureStore store, String target) async {
    final parsed = parseHostPaste(target);
    final data = store.snapshot().valueOrNull;
    final conns = data?.connections ?? const <Connection>[];

    final decision = route(
      parsed,
      conns,
      resolvedHost: _resolvedHost,
      resolvedPort: (c) => _resolvedPort(store, c),
      labelOf: (c) => c.label,
      isConnectable: (c) => _paramsFor(store, c) != null,
    );

    if (decision.route == QuickRoute.ephemeralSaved &&
        decision.connection != null) {
      final conn = decision.connection!;
      final params = _paramsFor(store, conn);
      if (params == null) return; // defensive; router already checked
      // Record the target BEFORE the (possibly slow / failing) connect so the
      // recents list reflects intent; only the `user@host:port` string — no
      // secret (ADR 0034 D4).
      ref
          .read(recentTargetsControllerProvider.notifier)
          .add(_targetFor(store, conn));
      // EPHEMERAL: _connect does NOT persist — no new vault entry (D2).
      await _connect(params, label: conn.label, conn: conn);
      return;
    }

    // Fallback: open the prefilled full dialog for a brand-new host (D2). The
    // bar itself NEVER persists; saving is the dialog's job (D5).
    await _openConnect(
      prefill: ConnectPrefill(
        host: parsed.host,
        port: parsed.port,
        username: parsed.username,
      ),
    );
  }

  Future<void> _connectSaved(SecureStore store, Connection c) async {
    final params = _paramsFor(store, c);
    if (params == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu bağlantı için kayıtlı kimlik bulunamadı.'),
          ),
        );
      }
      return;
    }
    await _connect(params, label: c.label, conn: c);
  }

  /// Opens an SFTP session for a saved connection. Mirrors [_connectSaved] but
  /// drives the SFTP service/view: resolves credentials via the SAME
  /// [_paramsFor] as the terminal path, closes any previous SFTP session,
  /// connects, switches to the SFTP view, and verifies the host key through the
  /// SHARED [_decideHostKey] helper (same coordinator + pins + dialog +
  /// pin-write rule as the terminal connect). One active SFTP session at a time.
  Future<void> _openSftp(SecureStore store, Connection c) async {
    final params = _paramsFor(store, c);
    if (params == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı veya kimlik çözülemedi — SFTP açılamıyor'),
          ),
        );
      }
      return;
    }

    // Close any previous SFTP session before opening a new one (single session)
    // and cancel its event subscriptions so they don't leak across sessions.
    await _cancelSftpSubs();
    final prev = ref.read(sftpSessionProvider);
    await prev?.close();

    final SftpSession session;
    try {
      session = await SftpService().connect(params);
    } catch (_) {
      // Isolate spawn / handshake failure must surface, not hang silently.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SFTP bağlantısı başlatılamadı')),
        );
      }
      return;
    }

    // Subscribe BEFORE publishing the session / switching the view: a host-key
    // request can arrive immediately after connect, and listening only after
    // the view transition opens a window where that request is missed. The
    // subscriptions are retained so the next open (or dispose) can cancel them.
    _sftpHostKeySub = session.hostKeyRequests.listen((req) async {
      final accept = await _decideHostKey(
        params,
        keyType: req.keyType,
        sha256: req.sha256,
      );
      session.decideHostKey(accept);
    });
    _sftpErrorSub = session.connectErrors.listen((err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('SFTP: ${err.message}')));
      }
    });

    ref.read(sftpSessionProvider.notifier).state = session;
    ref.read(sftpHostProvider.notifier).state = c.label;
    // Carry host context into the SFTP tab's default title ("SFTP · host",
    // ADR 0036 D3) so SFTP panes are distinguishable, not a bare 'SFTP'.
    ref
        .read(tabsControllerProvider.notifier)
        .openOrFocus(TabKind.sftp, host: c.label.isNotEmpty ? c.label : c.host);
    // The SFTP session tab is now active; leave the home/welcome (ADR 0022).
    ref.read(homeRequestedProvider.notifier).state = false;
  }

  // ---------------------------------------------------------------------------
  // Build.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Sidebar "+" (and our own button) bump newHostRequestProvider; open the
    // connect dialog when the counter changes.
    ref.listen<int>(newHostRequestProvider, (prev, next) {
      if (prev != null && next != prev) _openConnect();
    });

    // Connect-from-tree (ADR 0035 D4): the sidebar emits a ConnectRequest on
    // double-click / Enter / context-menu "Bağlan"; route it through the same
    // saved-connect path as the detail card's "Bağlan" button.
    ref.listen<ConnectRequest?>(connectRequestProvider, (prev, next) async {
      if (next == null || next.seq == (prev?.seq ?? 0)) return;
      final store = await ref.read(secureStoreProvider.future);
      if (!mounted) return;
      await _connectSaved(store, next.connection);
    });

    final storeAsync = ref.watch(secureStoreProvider);
    return storeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e', style: context.ui())),
      data: (store) => ListenableBuilder(
        listenable: store.revision,
        builder: (context, _) => _body(context, store),
      ),
    );
  }

  Widget _body(BuildContext context, SecureStore store) {
    final c = context.c;
    final data = store.snapshot().valueOrNull;
    final conns = data?.connections ?? const <Connection>[];
    final identities = data?.identities ?? const <Identity>[];

    // Resolve the selected connection against the live list (it may have been
    // removed/renamed). Fall back to null if not found.
    final selectedId = ref.watch(selectedConnectionProvider)?.id;
    final selected = connectionById(conns, selectedId);

    // When this welcome surface is shown over open sessions (nav rail
    // "Bağlantılar" / a sidebar selection), offer an explicit way back to them
    // (ADR 0022, §9).
    final sessionCount = ref.watch(tabsControllerProvider).tabs.length;

    // Live host-status lookup feeds the host cards / detail (ADR 0032 D6).
    final hostStatuses = ref.watch(hostStatusProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sessionCount > 0) ...[
            _BackToSessions(count: sessionCount),
            const SizedBox(height: 16),
          ],
          // Header.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bağlantı Yöneticisi',
                      style: context.ui(size: 22, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${conns.length} kayıtlı bağlantı'
                      ' · ${data?.pins.length ?? 0} bilinen host',
                      style: context.ui(size: 13, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              PrimaryButton(
                label: 'Yeni Host',
                icon: Icons.add,
                onPressed: () => _openConnect(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick connect (ADR 0034): ephemeral-by-default omnibox. Recents +
          // saved hosts feed the suggestions; routing/connecting is ours.
          QuickConnectBar(
            onConnectTarget: (target) => _quickConnect(store, target),
            recents: ref.watch(recentTargetsControllerProvider),
            saved: conns,
            displayOf: (cn) => cn.label,
            targetOf: (cn) => _targetFor(store, cn),
            hostOf: (cn) => cn.host,
            onRemoveRecent: (t) =>
                ref.read(recentTargetsControllerProvider.notifier).remove(t),
            onClearHistory: () =>
                ref.read(recentTargetsControllerProvider.notifier).clear(),
          ),
          const SizedBox(height: 24),

          // All saved connections (ADR 0035 D5): the old "Son Bağlananlar"
          // label was inaccurate — this grid shows every saved host in store
          // order, not a recency/MRU list. Real MRU recents is pass-2.
          const SectionLabel('Kayıtlı Bağlantılar'),
          const SizedBox(height: 12),
          if (conns.isEmpty)
            _EmptyState()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 14.0;
                final twoCol = constraints.maxWidth >= 520;
                final cardWidth = twoCol
                    ? (constraints.maxWidth - gap) / 2
                    : constraints.maxWidth;
                final folders = data?.folders ?? const <Folder>[];
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final cn in conns)
                      Builder(
                        builder: (context) {
                          final r = resolve(cn, folders);
                          final user = r.username ?? '?';
                          // Live session status for this host (ADR 0032 D6):
                          // the dot reflects an open session, not a const false.
                          final liveStatus =
                              hostStatuses['${cn.host}:${r.port}'];
                          return SizedBox(
                            width: cardWidth,
                            child: HostCard(
                              name: cn.label,
                              addr: '$user@${cn.host}:${r.port}',
                              connected: liveStatus?.isConnected ?? false,
                              status: liveStatus,
                              selected: cn.id == selectedId,
                              tags: [for (final t in cn.tags) Tag(text: t)],
                              onTap: () =>
                                  ref
                                          .read(
                                            selectedConnectionProvider.notifier,
                                          )
                                          .state =
                                      cn,
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 24),

          // Selected host detail.
          const SectionLabel('Seçili Host'),
          const SizedBox(height: 12),
          if (selected == null)
            Text(
              'Detay için bir host seçin.',
              style: context.ui(size: 13, color: c.textDim),
            )
          else
            Builder(
              builder: (context) {
                final folders = data?.folders ?? const <Folder>[];
                final resolved = resolve(selected, folders);
                return HostDetailCard(
                  connection: selected,
                  resolved: resolved,
                  identity: identityById(identities, resolved.authRef ?? ''),
                  folders: folders,
                  // Live session status for this host (ADR 0032 D6).
                  status: hostStatuses['${selected.host}:${resolved.port}'],
                  onConnect: () => _connectSaved(store, selected),
                  onEdit: () => editConnectionFlow(context, ref, selected),
                  onOpenSftp: () => _openSftp(store, selected),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// A compact banner shown atop the welcome surface when sessions are open, so
/// the user can jump back to them (the home was brought forward over live
/// sessions — ADR 0022, §9).
class _BackToSessions extends ConsumerWidget {
  final int count;
  const _BackToSessions({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Tooltip(
      message: 'Açık oturumlara geri dön',
      child: GestureDetector(
        key: const Key('backToSessions'),
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(homeRequestedProvider.notifier).state = false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, size: 15, color: c.accent),
              const SizedBox(width: 8),
              Text(
                'Oturumlara dön',
                style: context.ui(size: 12.5, weight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Text(
                '· $count açık oturum',
                style: context.ui(size: 12, color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
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
          Icon(Icons.dns_outlined, size: 36, color: c.textDim),
          const SizedBox(height: 12),
          Text(
            'Henüz kayıtlı bağlantı yok',
            style: context.ui(
              size: 14,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Bir sunucuya bağlanmak için "Yeni Host" veya hızlı bağlantıyı kullanın.',
            style: context.ui(size: 12.5, color: c.textDim),
          ),
        ],
      ),
    );
  }
}
