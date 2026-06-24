import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/models/connection.dart';
import '../../data/models/host_key_pin.dart';
import '../../data/resolve/connection_params.dart';
import '../../services/docker/docker_host.dart';
import '../../services/ssh/ssh_messages.dart';
import '../../services/ssh/terminal_session.dart';
import '../connect/host_key_dialog.dart';
import '../connections/host_key_policy.dart';
import '../shell/shell_state.dart';
import '../sftp/sftp_providers.dart';
import 'docker_providers.dart';

/// Opens an interactive terminal tab running `docker exec -it` inside [ct] on the
/// Docker-marked connection [conn]. Reuses the SAME pipeline as a plain SSH
/// shell: [SshDockerHost.execShell] returns a [TerminalSession] (an [SshSession]
/// at runtime) that we drive through the identical connect→host-key→ready flow as
/// `ConnectionsView._connect`, then hand to [TabsController.openTerminal] (ADR
/// 0028, §9).
///
/// Host-key trust is verified through the SHARED [HostKeyPolicy]/coordinator +
/// stored pins (see [_decideContainerHostKey]). A Docker host is already pinned
/// (it was trusted when the SSH connection was first made), so the common path
/// auto-accepts; an unknown/mismatched key still surfaces the host-key dialog.
Future<void> openContainerTerminal(
  BuildContext context,
  WidgetRef ref,
  Connection conn,
  DockerContainer ct,
) async {
  final store = await ref.read(secureStoreProvider.future);
  final data = store.snapshot().valueOrNull;
  final host = data == null ? null : dockerHostForConnection(data, conn.id);
  // host != null implies data != null (host is derived from it), but the
  // analyzer can't see that through the ternary — bail explicitly so `data` is
  // promoted to non-null for the params re-resolution below.
  if (data == null || host == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Docker bağlantısı çözümlenemedi')),
      );
    }
    return;
  }

  // execShell opens its own fresh SshService connection independent of the
  // host's shared client, so disposing the host immediately is safe — we keep
  // only the returned interactive session.
  final TerminalSession session;
  try {
    session = await host.execShell(ct.id);
  } catch (_) {
    // Spawn/handshake failure (rare, app-level) before any session exists —
    // there is no pane to host the error card, so a transient notice remains.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Container terminali açılamadı')),
      );
    }
    return;
  } finally {
    await host.dispose();
  }

  // Re-resolve the SAME params the host used so host-key verification has the
  // host/port to evaluate the presented key against the stored pins.
  final params = paramsFor(
    conn,
    folders: data.folders,
    identities: data.identities,
  );

  // Host-key verification runs over the live stream while the pane shows
  // "connecting"; the controller ignores HostKeyRequestEvent so this dedicated
  // subscription drives the dialog and responds, then cancels on resolution.
  // SSH-level connect failures (auth/network) surface as the SAME in-pane error
  // card as a plain shell — no SnackBar (ADR 0032 D3).
  late final StreamSubscription sub;
  sub = session.events.listen((e) async {
    if (e is HostKeyRequestEvent) {
      // The decision helper guards every BuildContext use behind
      // `context.mounted`, so passing it across this async listener is safe.
      final accept = params == null
          ? false
          : await _decideContainerHostKey(
              ref,
              // ignore: use_build_context_synchronously
              context,
              params,
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

  // Open the container terminal tab IMMEDIATELY (in `connecting`) so the
  // connecting overlay + persistent error card surface every phase, exactly
  // like a plain SSH shell (ADR 0032 D2/D3). The session is a TerminalSession
  // (an SshSession at runtime), so it drives the identical controller/view.
  final hostPort = params == null ? null : '${params.host}:${params.port}';
  ref
      .read(tabsControllerProvider.notifier)
      .openTerminal(
        session,
        '🐳 ${ct.name} @ ${conn.host}',
        hostPort: hostPort,
        // Reopen (Cmd/Ctrl+Shift+T) replays the FULL flow — a new exec
        // session + host-key verification — so reopening stays secure rather
        // than reusing a stale handle (ADR 0018/0028).
        reopen: () {
          if (context.mounted) {
            unawaited(openContainerTerminal(context, ref, conn, ct));
          }
        },
      );
  // A session is now front-and-center; leave the home/welcome (ADR 0022).
  ref.read(homeRequestedProvider.notifier).state = false;
}

/// Opens the SFTP view backed by a [DockerFileBackend] for [ct] on the
/// Docker-marked connection [conn], so the user can browse and transfer the
/// container's files through the SAME pane/queue/edit pipeline as a real SFTP
/// session (ADR 0028, §9). Backend-agnostic: [sftpSessionProvider] is typed as
/// [RemoteFileOps], so handing it a [DockerFileBackend] just works.
///
/// Unlike a real SFTP open there is NO connect/host-key step here: the Docker
/// host was already trusted when its SSH connection was first made, and the
/// backend connects lazily on first use. [SshDockerHost.files] returns a
/// self-contained backend (its own client for transfers; metadata reuses a
/// lazily-opened client) that does not depend on the host's shared client, so
/// the host is disposed immediately.
Future<void> openContainerFiles(
  BuildContext context,
  WidgetRef ref,
  Connection conn,
  DockerContainer ct,
) async {
  final store = await ref.read(secureStoreProvider.future);
  final data = store.snapshot().valueOrNull;
  final host = data == null ? null : dockerHostForConnection(data, conn.id);
  if (host == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Docker bağlantısı çözümlenemedi')),
      );
    }
    return;
  }

  final backend = host.files(ct.id);
  await host.dispose();

  // Single active file session: close any previous one before publishing.
  final prev = ref.read(sftpSessionProvider);
  await prev?.close();
  if (!context.mounted) return;

  ref.read(sftpSessionProvider.notifier).state = backend;
  ref.read(sftpHostProvider.notifier).state = '🐳 ${ct.name}';
  ref.read(tabsControllerProvider.notifier).openOrFocus(TabKind.sftp);
  // A file session is now front-and-center; leave the home/welcome (ADR 0022).
  ref.read(homeRequestedProvider.notifier).state = false;
}

/// Opens a terminal tab running `docker exec -it` inside the LOCAL container [ct].
/// Simpler than the remote path: a local PTY session is ready immediately, with
/// no SSH connect or host-key step. See ADR 0028/0029.
Future<void> openLocalContainerTerminal(
  BuildContext context,
  WidgetRef ref,
  DockerContainer ct,
) async {
  final host = ref.read(localDockerHostProvider);
  final TerminalSession session;
  try {
    session = await host.execShell(ct.id);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Container terminali açılamadı')),
      );
    }
    return;
  }
  if (!context.mounted) {
    await session.close();
    return;
  }
  ref
      .read(tabsControllerProvider.notifier)
      .openTerminal(
        session,
        '🐳 ${ct.name} (local)',
        reopen: () {
          if (context.mounted) {
            unawaited(openLocalContainerTerminal(context, ref, ct));
          }
        },
      );
  // A session is now front-and-center; leave the home/welcome (ADR 0022).
  ref.read(homeRequestedProvider.notifier).state = false;
}

/// Opens the SFTP view backed by a LOCAL [DockerFileBackend] for container [ct]
/// (browse + transfer via the same pane/queue as SFTP). No connect/host-key.
Future<void> openLocalContainerFiles(
  BuildContext context,
  WidgetRef ref,
  DockerContainer ct,
) async {
  final backend = ref.read(localDockerHostProvider).files(ct.id);
  // Single active file session: close any previous one before publishing.
  final prev = ref.read(sftpSessionProvider);
  await prev?.close();
  if (!context.mounted) return;
  ref.read(sftpSessionProvider.notifier).state = backend;
  ref.read(sftpHostProvider.notifier).state = '🐳 ${ct.name} (local)';
  ref.read(tabsControllerProvider.notifier).openOrFocus(TabKind.sftp);
  // A file session is now front-and-center; leave the home/welcome (ADR 0022).
  ref.read(homeRequestedProvider.notifier).state = false;
}

/// Host-key trust decision for a container exec session. Mirrors
/// `ConnectionsView._decideHostKey` exactly — same [HostKeyPolicy], same
/// coordinator/pins, same first-use/mismatch dialog, same pin-write rule — so
/// opening a container terminal is governed by the identical MITM protection as
/// opening a plain shell (ADR 0018). Replicated rather than shared because the
/// connections-view method is private to its widget state.
Future<bool> _decideContainerHostKey(
  WidgetRef ref,
  BuildContext context,
  SshConnectParams params, {
  required String keyType,
  required String sha256,
}) async {
  final store = await ref.read(secureStoreProvider.future);
  final policy = HostKeyPolicy(ref.read(hostKeyCoordinatorProvider));
  final hostPort = '${params.host}:${params.port}';

  final pins = store.snapshot().valueOrNull?.pins ?? const <HostKeyPin>[];
  final d = policy.decide(
    hostPort: hostPort,
    keyType: keyType,
    sha256: sha256,
    pins: pins,
  );
  var accept = d.autoAccept ?? false;
  if (d.autoAccept == null && context.mounted) {
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
