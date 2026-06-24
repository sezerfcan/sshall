import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/folders/connection_ops.dart';
import '../../data/models/connection.dart';
import '../../data/models/folder.dart';
import '../../data/models/identity.dart';
import '../../data/resolve/connection_params.dart';
import '../../data/resolve/connection_resolver.dart';
import '../connect/edit_connection_dialog.dart';

String _newIdentityId() => 'id-${DateTime.now().microsecondsSinceEpoch}';

/// Opens the edit dialog for [conn] and applies the result (update or delete).
Future<void> editConnectionFlow(
    BuildContext context, WidgetRef ref, Connection conn) async {
  final store = await ref.read(secureStoreProvider.future);
  final data = store.snapshot().valueOrNull;
  final folders = data?.folders ?? const <Folder>[];
  final identities = data?.identities ?? const <Identity>[];
  final resolved = resolve(conn, folders);
  final identity = identityById(identities, conn.authRef ?? '');
  if (!context.mounted) return;

  final result = await showEditConnectionDialog(context,
      connection: conn,
      identity: identity,
      resolved: resolved,
      folders: folders);
  if (result == null) return;
  if (!context.mounted) return;

  if (result.delete) {
    final res = await store.mutate((v) => deleteConnection(v, conn.id));
    if (context.mounted && !res.isOk) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Silinemedi: ${res.failureOrNull?.message ?? 'bilinmeyen hata'}')));
    }
  } else {
    final res = await store.mutate((v) => updateConnection(v,
        connId: conn.id,
        label: result.label,
        host: result.host,
        folderId: result.folderId,
        tags: result.tags,
        username: result.username,
        port: result.port,
        identity: result.identity,
        docker: result.docker,
        dockerBinary: result.dockerBinary,
        newIdentityId: _newIdentityId()));
    if (context.mounted && !res.isOk) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Kaydedilemedi: ${res.failureOrNull?.message ?? 'bilinmeyen hata'}')));
    }
  }
}

/// Confirms and deletes [conn] without opening the edit dialog (sidebar path).
Future<void> deleteConnectionFlow(
    BuildContext context, WidgetRef ref, Connection conn) async {
  final ok = await confirmDeleteConnection(context, conn.label);
  if (!ok) return;
  final store = await ref.read(secureStoreProvider.future);
  final res = await store.mutate((v) => deleteConnection(v, conn.id));
  if (context.mounted && !res.isOk) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Silinemedi: ${res.failureOrNull?.message ?? 'bilinmeyen hata'}')));
  }
}
