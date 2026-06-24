import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/folders/connection_ops.dart';
import '../../data/folders/folder_ops.dart';
import '../../data/models/connection.dart';
import '../../data/models/folder.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';

/// The non-drag accessibility fallback for moving a host into a folder
/// (ADR 0035 D4 / macOS HIG): reuses the folder move-target picker pattern from
/// `folder_actions.dart`, then appends the host to the chosen folder via the pure
/// [moveConnection] op in a single atomic `store.mutate` revision.
Future<void> moveConnectionToFolderFlow(
  BuildContext context,
  WidgetRef ref,
  Connection conn,
) async {
  final store = await ref.read(secureStoreProvider.future);
  final folders = store.snapshot().valueOrNull?.folders ?? const <Folder>[];
  if (!context.mounted) return;

  final target = await showDialog<_ConnMoveTarget>(
    context: context,
    builder: (_) => _ConnMoveDialog(conn: conn, folders: folders),
  );
  if (target == null) return;

  await store.mutate((v) {
    // Append to the end of the destination folder's siblings.
    final order = nextOrder(
      v.connections
          .where((c) => c.id != conn.id && c.folderId == target.folderId)
          .map((c) => c.order),
    );
    return moveConnection(v, conn.id, folderId: target.folderId, order: order);
  });
}

/// Wraps a chosen folder so "Root" (null) is distinguishable from a dismissed
/// dialog (null result).
class _ConnMoveTarget {
  final String? folderId;
  const _ConnMoveTarget(this.folderId);
}

class _ConnMoveDialog extends StatelessWidget {
  final Connection conn;
  final List<Folder> folders;
  const _ConnMoveDialog({required this.conn, required this.folders});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text(
        'Klasöre taşı — ${conn.label}',
        style: context.ui(size: 16, weight: FontWeight.w600),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tile(context, 'Root (en üst)', const _ConnMoveTarget(null)),
              for (final f in folders)
                _tile(context, f.name, _ConnMoveTarget(f.id)),
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(label: 'Vazgeç', onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _tile(BuildContext context, String label, _ConnMoveTarget target) {
    final c = context.c;
    return InkWell(
      key: Key('move-conn-target-${target.folderId ?? 'root'}'),
      onTap: () => Navigator.pop(context, target),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 15, color: c.textMuted),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: context.ui(size: 13))),
          ],
        ),
      ),
    );
  }
}
