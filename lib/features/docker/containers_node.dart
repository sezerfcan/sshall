import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/docker/docker_host.dart';
import '../../theme/context_ext.dart';

/// The expandable list of containers shown under a Docker host (remote
/// per-connection or local) in the sidebar. Renders loading / error / empty /
/// list states (ADR 0028, §9).
///
/// This widget is presentation-only: the caller passes the already-watched
/// [containers] async value plus an [onRetry] callback, so both remote and
/// local Docker hosts can reuse it. Per-row actions are delegated to
/// [onOpenTerminal] / [onBrowse].
class ContainersNode extends StatelessWidget {
  const ContainersNode({
    super.key,
    required this.containers,
    required this.onRetry,
    required this.retryKeyId,
    required this.indent,
    required this.onOpenTerminal,
    required this.onBrowse,
  });

  final AsyncValue<List<DockerContainer>> containers;
  final VoidCallback onRetry;

  /// Disambiguates the retry InkWell's `Key('container-retry-$retryKeyId')`
  /// when multiple [ContainersNode]s coexist (e.g. several remote hosts + local).
  final String retryKeyId;
  final double indent;
  final void Function(DockerContainer) onOpenTerminal;
  final void Function(DockerContainer) onBrowse;

  @override
  Widget build(BuildContext context) {
    return containers.when(
      loading: () => _loadingRow(context),
      error: (e, _) => _errorRow(context, e),
      data: (list) => list.isEmpty
          ? _infoRow(context, 'Container yok')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final ct in list) _containerRow(context, ct),
              ],
            ),
    );
  }

  Widget _loadingRow(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 6, 8, 6),
      child: Row(children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: c.textDim),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text("Container'lar yükleniyor…",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 11.5, color: c.textDim)),
        ),
      ]),
    );
  }

  Widget _infoRow(BuildContext context, String message) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 6, 8, 6),
      child: Text(message, style: context.ui(size: 11.5, color: c.textDim)),
    );
  }

  Widget _errorRow(BuildContext context, Object error) {
    final c = context.c;
    final message = _errorMessage(error);
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 6, 8, 6),
      child: Row(children: [
        Icon(Icons.error_outline, size: 14, color: c.red),
        const SizedBox(width: 7),
        Expanded(
          child: Text(message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 11.5, color: c.red)),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Yeniden dene',
          child: InkWell(
            key: Key('container-retry-$retryKeyId'),
            onTap: onRetry,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.refresh, size: 15, color: c.textMuted),
            ),
          ),
        ),
      ]),
    );
  }

  /// Maps a [DockerException] to a precise, actionable Turkish message; any other
  /// error falls back to its string form (§9 — never a bare stack trace).
  String _errorMessage(Object error) {
    if (error is DockerException) {
      switch (error.kind) {
        case DockerErrorKind.notInstalled:
          return 'Docker bulunamadı';
        case DockerErrorKind.denied:
          return 'Docker erişim yetkisi yok';
        case DockerErrorKind.daemonNotRunning:
          return 'Docker çalışmıyor — Docker Desktop\'ı başlatın';
        case DockerErrorKind.unknown:
          return error.message.isEmpty ? 'Docker hatası' : error.message;
      }
    }
    return error.toString();
  }

  Widget _containerRow(BuildContext context, DockerContainer ct) {
    final c = context.c;
    final running = ct.isRunning;
    final subtitle = [
      ct.image,
      if (ct.ports.isNotEmpty) ct.ports.join(', '),
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 5, 6, 5),
      child: Row(children: [
        // Leading status dot: ● running (green) / ○ otherwise (dim).
        Tooltip(
          message: ct.status,
          child: Text(running ? '●' : '○',
              style: context.mono(
                  size: 11, color: running ? c.green : c.textDim)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ct.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.ui(size: 12)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mono(size: 9.5, color: c.textDim)),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _action(
          context,
          key: 'container-terminal-${ct.id}',
          icon: Icons.terminal,
          enabled: running,
          tooltip: running
              ? 'Terminal aç'
              : 'Yalnızca çalışan container için',
          onTap: () => onOpenTerminal(ct),
        ),
        const SizedBox(width: 2),
        _action(
          context,
          key: 'container-browse-${ct.id}',
          icon: Icons.folder_open_outlined,
          enabled: true,
          tooltip: 'Dosyalara gözat',
          onTap: () => onBrowse(ct),
        ),
      ]),
    );
  }

  Widget _action(
    BuildContext context, {
    required String key,
    required IconData icon,
    required bool enabled,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: Key(key),
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon,
              size: 15,
              color: enabled ? c.textMuted : c.textDim.withValues(alpha: .5)),
        ),
      ),
    );
  }
}
