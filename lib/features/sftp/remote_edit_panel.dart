import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../theme/context_ext.dart';
import 'remote_edit_session.dart';

/// Bottom panel listing active remote-edit sessions (D3). One row per open
/// file: status, message (on error/conflict), conflict resolution actions, and
/// a "Bitir" action that stops watching + cleans up the temp copy.
class RemoteEditPanel extends StatelessWidget {
  final List<RemoteEditSession> sessions;
  final void Function(String id) onFinish;
  final void Function(String id, ConflictChoice choice) onResolve;

  const RemoteEditPanel({
    super.key,
    required this.sessions,
    required this.onFinish,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Düzenlenen uzak dosyalar',
                style: context.ui(size: 11, color: c.textDim)),
          ),
          for (final s in sessions) _row(context, s),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, RemoteEditSession s) {
    final c = context.c;
    final showMsg = s.message != null &&
        (s.status == RemoteEditStatus.error ||
            s.status == RemoteEditStatus.conflict ||
            s.status == RemoteEditStatus.closedRemote);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 14, color: c.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(p.basename(s.remotePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.ui(size: 12, color: c.text)),
              ),
              _statusChip(context, s.status),
              const SizedBox(width: 8),
              Tooltip(
                message: 'İzlemeyi durdur ve geçici kopyayı sil',
                child: TextButton(
                  onPressed: () => onFinish(s.id),
                  child: Text('Bitir', style: context.ui(size: 11)),
                ),
              ),
            ],
          ),
          if (showMsg)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(s.message!,
                  style: context.ui(size: 11, color: c.textMuted)),
            ),
          if (s.status == RemoteEditStatus.conflict)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => onResolve(s.id, ConflictChoice.overwriteRemote),
                    child: const Text('Uzağı ez'),
                  ),
                  TextButton(
                    onPressed: () => onResolve(s.id, ConflictChoice.saveAsLocal),
                    child: const Text('Farklı kaydet'),
                  ),
                  TextButton(
                    onPressed: () => onResolve(s.id, ConflictChoice.keepEditing),
                    child: const Text('Devam'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, RemoteEditStatus st) {
    final c = context.c;
    final (label, color) = switch (st) {
      RemoteEditStatus.downloading => ('İndiriliyor', c.textDim),
      RemoteEditStatus.watching => ('İzleniyor', c.green),
      RemoteEditStatus.uploading => ('Yükleniyor', c.accent),
      RemoteEditStatus.conflict => ('Çakışma', c.red),
      RemoteEditStatus.error => ('Hata', c.red),
      RemoteEditStatus.closedRemote => ('Kapandı', c.textDim),
    };
    return Text(label, style: context.ui(size: 11, color: color));
  }
}
