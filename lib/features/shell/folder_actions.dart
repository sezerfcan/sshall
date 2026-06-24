import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/folders/folder_ops.dart';
import '../../data/models/folder.dart';
import '../../data/resolve/connection_resolver.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/buttons.dart';

String _newFolderId() => 'f-${DateTime.now().microsecondsSinceEpoch}';

/// Prompts for a name and creates a folder under [parentId] (null = root).
Future<void> createFolderFlow(
  BuildContext context,
  WidgetRef ref, {
  String? parentId,
}) async {
  final name = await _promptName(
    context,
    title: 'Yeni klasör',
    initial: '',
  );
  if (name == null || name.isEmpty) return;
  final store = await ref.read(secureStoreProvider.future);
  await store.mutate(
      (v) => addFolder(v, id: _newFolderId(), parentId: parentId, name: name));
}

/// Prompts (prefilled) and renames [folder].
Future<void> renameFolderFlow(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final name = await _promptName(
    context,
    title: 'Yeniden adlandır',
    initial: folder.name,
  );
  if (name == null || name.isEmpty) return;
  final store = await ref.read(secureStoreProvider.future);
  await store.mutate((v) => renameFolder(v, folder.id, name));
}

/// Lets the user pick a new parent (Root + every non-cyclic folder) and moves
/// [folder] there.
Future<void> moveFolderFlow(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final store = await ref.read(secureStoreProvider.future);
  final folders = store.snapshot().valueOrNull?.folders ?? const <Folder>[];
  // Offer Root + every folder that isn't the folder itself and wouldn't create
  // a cycle. (moveFolder is already a no-op on cycles; this just hides them.)
  final candidates = folders
      .where((f) =>
          f.id != folder.id &&
          !wouldCreateCycle(folder.id, f.id, folders))
      .toList();
  if (!context.mounted) return;

  final target = await showDialog<_MoveTarget>(
    context: context,
    builder: (_) => _MoveDialog(folder: folder, candidates: candidates),
  );
  if (target == null) return;
  await store.mutate((v) => moveFolder(v, folder.id, target.parentId));
}

/// Confirms, then deletes [folder] re-parenting its contents to the parent.
Future<void> deleteFolderFlow(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.c;
      return AlertDialog(
        backgroundColor: c.elevated,
        title: Text('Klasör silinsin mi?',
            style: ctx.ui(size: 16, weight: FontWeight.w600)),
        content: Text(
          '"${folder.name}" silinecek. İçindekiler üst klasöre taşınır.',
          style: ctx.ui(size: 13, color: c.textMuted),
        ),
        actions: [
          GhostButton(
            label: 'Vazgeç',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          PrimaryButton(
            label: 'Sil',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  final store = await ref.read(secureStoreProvider.future);
  await store.mutate((v) => deleteFolderReparent(v, folder.id));
}

/// Single-field name prompt. Returns the trimmed name, or null if cancelled.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = ctx.c;
      return AlertDialog(
        backgroundColor: c.elevated,
        title: Text(title, style: ctx.ui(size: 16, weight: FontWeight.w600)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppTextField(
            controller: controller,
            label: 'Klasör adı',
            autofocus: true,
            fieldKey: const Key('folderName'),
            onSubmitted: (_) =>
                Navigator.pop(ctx, controller.text.trim()),
          ),
        ),
        actions: [
          GhostButton(
            label: 'Vazgeç',
            onPressed: () => Navigator.pop(ctx),
          ),
          PrimaryButton(
            label: 'Kaydet',
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}

/// Wraps a chosen move target so "Root" (null parent) is distinguishable from
/// "dialog dismissed" (null result).
class _MoveTarget {
  final String? parentId;
  const _MoveTarget(this.parentId);
}

class _MoveDialog extends StatelessWidget {
  final Folder folder;
  final List<Folder> candidates;
  const _MoveDialog({required this.folder, required this.candidates});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.elevated,
      title: Text('Taşı — ${folder.name}',
          style: context.ui(size: 16, weight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _targetTile(context, 'Root (en üst)', const _MoveTarget(null)),
              for (final f in candidates)
                _targetTile(context, f.name, _MoveTarget(f.id)),
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Vazgeç',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _targetTile(BuildContext context, String label, _MoveTarget target) {
    final c = context.c;
    return InkWell(
      onTap: () => Navigator.pop(context, target),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Icon(Icons.folder_outlined, size: 15, color: c.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: context.ui(size: 13))),
        ]),
      ),
    );
  }
}
