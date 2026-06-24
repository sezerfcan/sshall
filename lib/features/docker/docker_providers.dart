import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/models/vault_data.dart';
import '../../data/resolve/connection_params.dart';
import '../../services/docker/docker_host.dart';
import '../../services/docker/local_docker_host.dart';
import '../../services/docker/ssh_docker_host.dart';

/// Builds an [SshDockerHost] for the connection [connId] within [data], or null
/// when the connection is missing, not a Docker host, or not yet connectable
/// (username/authRef unresolved, or a dangling identity reference).
///
/// Pure: no `ref`, no store — so it can be unit-tested with a hand-built
/// [VaultData] and is REUSABLE by Task 11's terminal/SFTP handlers, which need
/// the same "connection -> docker host" mapping.
SshDockerHost? dockerHostForConnection(VaultData data, String connId) {
  final conn = connectionById(data.connections, connId);
  if (conn == null || !conn.docker) return null;
  final params = paramsFor(
    conn,
    folders: data.folders,
    identities: data.identities,
  );
  if (params == null) return null;
  return SshDockerHost(params, binary: conn.dockerBinary ?? 'docker');
}

/// Lists the containers for the Docker-marked connection [connId]. Returns an
/// empty list when the store/connection/host cannot be resolved, and surfaces a
/// [DockerException] (from `docker ps`) as an [AsyncError] for the UI to map.
///
/// The host opens its own SSH client for the listing, so it is disposed once
/// the list completes (or throws). Re-fetch with
/// `ref.invalidate(containerListProvider(connId))`.
final containerListProvider =
    FutureProvider.family<List<DockerContainer>, String>((ref, connId) async {
  final store = await ref.watch(secureStoreProvider.future);
  final data = store.snapshot().valueOrNull;
  if (data == null) return const [];
  final host = dockerHostForConnection(data, connId);
  if (host == null) return const [];
  try {
    return await host.listContainers();
  } finally {
    await host.dispose();
  }
});

/// Connection ids whose Docker container section is expanded in the sidebar.
/// Mirrors `expandedFoldersProvider` for the folder tree.
final expandedDockerProvider = StateProvider<Set<String>>((ref) => <String>{});

/// The single local Docker host (drives the local `docker` CLI). Overridable in
/// tests with an injected ProcessRunner. See ADR 0028/0029.
final localDockerHostProvider =
    Provider<LocalDockerHost>((ref) => LocalDockerHost());

/// Lists the LOCAL daemon's containers. Surfaces a [DockerException] (not
/// installed / daemon down / denied) as an [AsyncError] for the UI to map.
/// Re-fetch with `ref.invalidate(localContainerListProvider)`.
final localContainerListProvider =
    FutureProvider<List<DockerContainer>>((ref) async {
  final host = ref.watch(localDockerHostProvider);
  return host.listContainers();
});

/// Whether the "Local Docker" node is expanded in the sidebar.
final localDockerExpandedProvider = StateProvider<bool>((ref) => false);
