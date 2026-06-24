import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import 'shell_metrics.dart';

/// The three DISTINCT empty states of the connection tree (ADR 0035 D2). They
/// never collapse into a single shared "Kayıt yok" — each guides the user toward
/// the right next action (§9 discoverability).

/// (a) First-run: zero connections, no search. Centered icon + title + subtitle
/// + a real primary CTA that opens the new-connection flow.
class FirstRunEmptyState extends StatelessWidget {
  const FirstRunEmptyState({super.key, required this.onNewHost});

  final VoidCallback onNewHost;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          key: const Key('sidebar-empty-firstrun'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 40, color: c.textDim),
            const SizedBox(height: 14),
            Text(
              'Henüz bağlantı yok',
              textAlign: TextAlign.center,
              style: context.ui(size: 14, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'İlk sunucunu ekleyerek başla. '
              'Hostları klasörlerde gruplayabilirsin.',
              textAlign: TextAlign.center,
              style: context.ui(size: 12, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            Tooltip(
              message: 'Yeni bir SSH bağlantısı ekle',
              child: PrimaryButton(
                key: const Key('sidebar-empty-firstrun-cta'),
                label: 'Yeni bağlantı',
                icon: Icons.add,
                onPressed: onNewHost,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// (c) No search results: echoes the query, offers a one-tap clear, and names
/// the search scope so the user knows what was searched.
class NoSearchResultsState extends StatelessWidget {
  const NoSearchResultsState({
    super.key,
    required this.query,
    required this.onClear,
  });

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          key: const Key('sidebar-empty-noresults'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 30, color: c.textDim),
            const SizedBox(height: 12),
            Text(
              '"$query" için sonuç yok',
              textAlign: TextAlign.center,
              style: context.ui(size: 13, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Ad, host, etiket veya kullanıcı aranıyor.',
              textAlign: TextAlign.center,
              style: context.ui(size: 11.5, color: c.textDim),
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: 'Aramayı temizle ve tüm bağlantıları göster',
              child: GhostButton(
                key: const Key('sidebar-empty-noresults-clear'),
                label: 'Aramayı temizle',
                onPressed: onClear,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// (b) Empty expanded folder: an indented, muted inline hint woven into the tree
/// directly under the folder's row (it doubles as a drop target — wired by the
/// sidebar). Distinct copy that invites a drag.
class EmptyFolderHint extends StatelessWidget {
  const EmptyFolderHint({super.key, required this.depth});

  final int depth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Align under a host row at this folder's depth (folder depth + 1).
    final indent =
        ShellMetrics.sidebarBaseIndent +
        (depth + 1) * ShellMetrics.sidebarIndentStep +
        ShellMetrics.hostRowIndent;
    return Padding(
      key: const Key('sidebar-empty-folder-hint'),
      padding: EdgeInsets.fromLTRB(
        indent,
        ShellMetrics.rowVerticalPadding,
        8,
        ShellMetrics.rowVerticalPadding,
      ),
      child: Row(
        children: [
          Icon(Icons.south_east, size: 12, color: c.textDim),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Boş klasör — buraya host sürükleyin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 11.5, color: c.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
