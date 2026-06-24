import 'package:flutter/material.dart';

import '../../data/models/connection.dart';
import '../../data/models/folder.dart';
import '../../data/models/identity.dart';
import '../../data/resolve/connection_resolver.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import '../../widgets/status_pill.dart';
import '../terminal/session_status.dart';

/// Which inheritable field a meta cell describes (used to find the source
/// folder for the "↳ miras" marker by walking the folder chain).
enum _Field { port, authRef }

/// Detail card for the currently selected [Connection]. Shows the server icon,
/// name + status, `user@host:port`, a disabled edit action and a "Bağlan"
/// primary button, plus a 4-cell meta grid (Port, Kimlik, Klasör, Şifreleme).
class HostDetailCard extends StatelessWidget {
  final Connection connection;

  /// The connection's inheritable fields resolved against the folder chain.
  final ResolvedConnection resolved;

  /// The resolved identity for this connection (used for the "Kimlik" cell).
  /// Null when the identity is missing.
  final Identity? identity;

  /// All folders, used to render the "Klasör" cell name and to name the source
  /// folder of an inherited value in the "↳ miras" tooltip.
  final List<Folder> folders;
  final VoidCallback onConnect;

  /// Opens the edit dialog for this connection. Null disables the edit action.
  final VoidCallback? onEdit;

  /// Opens an SFTP file-transfer session for this connection. Null disables the
  /// "SFTP" action.
  final VoidCallback? onOpenSftp;

  /// Live session status for this host (ADR 0032 D6). Null = no open session
  /// (idle): the pill reads "Bağlı değil". Non-null drives the real label +
  /// pill state.
  final SessionStatus? status;

  /// Negotiated cipher when connected (ADR 0032 D6). Null hides the value
  /// behind a placeholder.
  final String? cipher;

  const HostDetailCard({
    super.key,
    required this.connection,
    required this.resolved,
    required this.identity,
    required this.folders,
    required this.onConnect,
    this.onEdit,
    this.onOpenSftp,
    this.status,
    this.cipher,
  });

  String get _authLabel => switch (identity?.type) {
    IdentityType.password => 'Parola',
    IdentityType.privateKey => 'Özel Anahtar',
    null => '—',
  };

  /// Folder name for [connection.folderId]; 'Kök' when at root or missing.
  String get _folderName {
    for (final f in folders) {
      if (f.id == connection.folderId) return f.name;
    }
    return 'Kök';
  }

  /// Walks the folder chain from [connection] upward and returns the name of
  /// the first ancestor folder that sets [field]. null when none does (then a
  /// generic tooltip is used). Cycle-guarded, mirroring `resolve()`.
  String? _sourceFolderName(_Field field) {
    final byId = {for (final f in folders) f.id: f};
    final visited = <String>{};
    String? parentId = connection.folderId;
    while (parentId != null &&
        byId.containsKey(parentId) &&
        visited.add(parentId)) {
      final f = byId[parentId]!;
      final set = switch (field) {
        _Field.port => f.port != null,
        _Field.authRef => f.authRef != null,
      };
      if (set) return f.name;
      parentId = f.parentId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final user = resolved.username ?? '?';
    final addr = '$user@${connection.host}:${resolved.port}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.green.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.dns_outlined, size: 20, color: c.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            connection.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.ui(
                              size: 16,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Real, live status (ADR 0032 D6): retires the const
                        // "Bağlı değil". Idle (no session) still reads that.
                        StatusPill(
                          label: status == null
                              ? 'Bağlı değil'
                              : statusLabel(status!),
                          connected: status?.isConnected ?? false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(addr, style: context.mono(size: 12, color: c.textDim)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: onEdit == null
                    ? 'Bağlantı düzenleme yakında'
                    : 'Bağlantıyı düzenle',
                child: AppIconButton(
                  icon: Icons.edit_outlined,
                  onPressed: onEdit,
                ),
              ),
              const SizedBox(width: 8),
              PrimaryButton(label: 'Bağlan', onPressed: onConnect),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Bu sunucuda dosya aktarımı (SFTP) aç',
                child: SecondaryButton(label: 'SFTP', onPressed: onOpenSftp),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _meta(
                context,
                'Port',
                '${resolved.port}',
                // Own value is null but a value resolved ⇒ inherited.
                inheritedFrom: connection.port == null
                    ? _sourceFolderName(_Field.port)
                    : null,
                inherited: connection.port == null,
              ),
              _meta(
                context,
                'Kimlik',
                _authLabel,
                inheritedFrom:
                    connection.authRef == null && resolved.authRef != null
                    ? _sourceFolderName(_Field.authRef)
                    : null,
                inherited:
                    connection.authRef == null && resolved.authRef != null,
              ),
              _meta(context, 'Klasör', _folderName),
              // Real negotiated cipher when connected (ADR 0032 D6); '—' until
              // a live session reports one.
              _meta(
                context,
                'Şifreleme',
                (status?.isConnected ?? false) && cipher != null
                    ? cipher!
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(
    BuildContext context,
    String label,
    String value, {
    bool inherited = false,
    String? inheritedFrom,
  }) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: context.ui(
              size: 10,
              weight: FontWeight.w700,
              color: c.textDim,
              spacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.ui(size: 13, color: c.textMuted),
          ),
          if (inherited) ...[
            const SizedBox(height: 2),
            Tooltip(
              message: inheritedFrom != null
                  ? '$inheritedFrom klasöründen miras'
                  : 'Üst klasörden miras alındı',
              child: Text(
                '↳ miras',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ui(size: 10, color: c.textDim),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
