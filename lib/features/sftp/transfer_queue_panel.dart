import 'package:flutter/material.dart';
import '../../services/sftp/transfer_queue.dart';
import '../../theme/context_ext.dart';
import 'fs_format.dart';

/// Bottom transfer queue panel (D7). One row per batch (a file or a folder = one
/// user action) with aggregate progress, file counts, speed/ETA and a summary.
///
/// Each batch expands to per-file sub-rows. Distinct controls: a stop_circle to
/// CANCEL in-flight work (attention tint) vs a close to DISMISS a finished batch
/// (dim) — no longer the same glyph. Failed items stay visible with a reason and
/// a "Yeniden dene". An overall summary line tops the panel; the panel itself is
/// collapsible with a count badge.
class TransferQueuePanel extends StatefulWidget {
  final List<BatchView> batches;
  final void Function(String batchId) onCancelBatch;
  final void Function(String batchId) onDismissBatch;
  final VoidCallback onClearFinished;

  /// Per-file jobs of a batch (D7 expansion). Defaults to empty.
  final List<TransferJob> Function(String batchId) jobsFor;

  /// Smoothed speed (bytes/sec) for a job id, or null when unknown (D7).
  final double? Function(int jobId) rateFor;

  /// Re-queue a whole failed batch / a single failed job (D7).
  final void Function(String batchId) onRetryBatch;
  final void Function(int jobId) onRetryJob;

  /// Collapse the panel to its summary + badge only.
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  const TransferQueuePanel({
    super.key,
    required this.batches,
    required this.onCancelBatch,
    required this.onDismissBatch,
    required this.onClearFinished,
    this.jobsFor = _noJobs,
    this.rateFor = _noRate,
    this.onRetryBatch = _noBatch,
    this.onRetryJob = _noJob,
    this.collapsed = false,
    this.onToggleCollapse = _noop,
  });

  static List<TransferJob> _noJobs(String _) => const [];
  static double? _noRate(int _) => null;
  static void _noBatch(String _) {}
  static void _noJob(int _) {}
  static void _noop() {}

  @override
  State<TransferQueuePanel> createState() => _TransferQueuePanelState();
}

class _TransferQueuePanelState extends State<TransferQueuePanel> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final batches = widget.batches;
    if (batches.isEmpty) return const SizedBox.shrink();
    final c = context.c;
    final hasFinished = batches.any((b) => b.finished);
    final activeBatches = batches.where((b) => b.inProgress).toList();

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
          _summaryBar(context, c, batches, activeBatches, hasFinished),
          if (!widget.collapsed) ...[
            for (final b in batches) _batchRow(context, c, b),
          ],
        ],
      ),
    );
  }

  Widget _summaryBar(
    BuildContext context,
    dynamic c,
    List<BatchView> batches,
    List<BatchView> active,
    bool hasFinished,
  ) {
    // Combined speed/ETA across active batches (D7 overall summary line).
    var combinedRate = 0.0;
    var remaining = 0;
    var anyRate = false;
    for (final b in active) {
      for (final j in widget.jobsFor(b.id)) {
        if (j.status == JobStatus.active) {
          final r = widget.rateFor(j.id);
          if (r != null && r > 0) {
            combinedRate += r;
            anyRate = true;
          }
        }
      }
      remaining += (b.totalBytes - b.bytes).clamp(0, b.totalBytes);
    }
    final eta = anyRate && combinedRate > 0
        ? Duration(milliseconds: (remaining / combinedRate * 1000).round())
        : null;

    final summary = active.isEmpty
        ? '${batches.length} aktarım'
        : '${active.length} aktarım'
              '${anyRate ? ' · ${humanRate(combinedRate)}' : ''}'
              '${eta != null ? ' · ~${humanEta(eta)}' : ''}';

    return Row(
      children: [
        Tooltip(
          message: widget.collapsed ? 'Genişlet' : 'Daralt',
          child: IconButton(
            key: const Key('queueCollapseToggle'),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              widget.collapsed ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: c.textMuted,
            ),
            onPressed: widget.onToggleCollapse,
          ),
        ),
        Icon(Icons.sync_alt, size: 14, color: c.accent),
        const SizedBox(width: 6),
        // Count badge.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${batches.length}',
            style: context.ui(
              size: 11,
              weight: FontWeight.w700,
              color: c.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.ui(size: 12, color: c.textMuted),
          ),
        ),
        if (hasFinished)
          Tooltip(
            message: 'Bitenleri temizle',
            child: TextButton.icon(
              onPressed: widget.onClearFinished,
              icon: const Icon(Icons.cleaning_services_outlined, size: 14),
              label: Text(
                'Bitenleri temizle',
                style: context.ui(size: 11, color: c.textMuted),
              ),
            ),
          ),
      ],
    );
  }

  Widget _batchRow(BuildContext context, dynamic c, BatchView b) {
    final expanded = _expanded.contains(b.id);
    final isFailed = b.failed > 0;
    // Aggregate speed/ETA for the batch from its active jobs.
    var rate = 0.0;
    var anyRate = false;
    for (final j in widget.jobsFor(b.id)) {
      if (j.status == JobStatus.active) {
        final r = widget.rateFor(j.id);
        if (r != null && r > 0) {
          rate += r;
          anyRate = true;
        }
      }
    }
    final remaining = (b.totalBytes - b.bytes).clamp(0, b.totalBytes);
    final eta = anyRate && rate > 0
        ? Duration(milliseconds: (remaining / rate * 1000).round())
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              // Expand/collapse caret.
              InkWell(
                key: Key('batchExpand_${b.id}'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() {
                  if (expanded) {
                    _expanded.remove(b.id);
                  } else {
                    _expanded.add(b.id);
                  }
                }),
                child: Icon(
                  expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: 18,
                  color: c.textMuted,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _label(b),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.ui(
                              size: 12,
                              color: isFailed ? c.red : c.textMuted,
                            ),
                          ),
                        ),
                        if (b.inProgress && !b.scanning)
                          Text(
                            '${humanSize(b.bytes)}/${humanSize(b.totalBytes)}'
                            '${anyRate ? ' · ${humanRate(rate)}' : ''}'
                            '${eta != null ? ' · ~${humanEta(eta)}' : ''}',
                            style: context.mono(size: 10, color: c.textDim),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: b.scanning
                          ? null
                          : (b.finished ? 1.0 : b.fraction),
                      minHeight: 3,
                      backgroundColor: c.border,
                      color: isFailed ? c.amber : c.accent,
                    ),
                  ],
                ),
              ),
              if (isFailed)
                Tooltip(
                  message: 'Yeniden dene',
                  child: IconButton(
                    key: Key('retryBatch_${b.id}'),
                    icon: Icon(Icons.refresh, size: 15, color: c.amber),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onRetryBatch(b.id),
                  ),
                ),
              if (b.finished)
                Tooltip(
                  message: 'Kaldır',
                  child: IconButton(
                    key: Key('dismissBatch_${b.id}'),
                    icon: Icon(Icons.close, size: 15, color: c.textDim),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onDismissBatch(b.id),
                  ),
                )
              else
                Tooltip(
                  message: 'İptal',
                  child: IconButton(
                    key: Key('cancelBatch_${b.id}'),
                    icon: Icon(Icons.stop_circle, size: 16, color: c.red),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onCancelBatch(b.id),
                  ),
                ),
            ],
          ),
        ),
        if (expanded) _subRows(context, c, b),
      ],
    );
  }

  Widget _subRows(BuildContext context, dynamic c, BatchView b) {
    final jobs = widget.jobsFor(b.id);
    if (jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 26, bottom: 4),
        child: Text(
          'Dosya yok (tümü atlandı)',
          style: context.ui(size: 11, color: c.textDim),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final j in jobs) _jobRow(context, c, j)],
      ),
    );
  }

  Widget _jobRow(BuildContext context, dynamic c, TransferJob j) {
    final (icon, tint) = switch (j.status) {
      JobStatus.done => (Icons.check_circle_outline, c.green),
      JobStatus.failed => (Icons.error_outline, c.red),
      JobStatus.cancelled => (Icons.cancel_outlined, c.textDim),
      JobStatus.active => (Icons.downloading, c.accent),
      JobStatus.queued => (Icons.schedule, c.textDim),
    };
    final frac = j.size > 0 ? (j.bytes / j.size).clamp(0.0, 1.0) : null;
    final rate = j.status == JobStatus.active ? widget.rateFor(j.id) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 6),
          SizedBox(
            width: 130,
            child: Text(
              j.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 11, color: c.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: j.status == JobStatus.done ? 1.0 : frac,
              minHeight: 2,
              backgroundColor: c.border,
              color: tint,
            ),
          ),
          const SizedBox(width: 8),
          if (j.status == JobStatus.failed) ...[
            Flexible(
              child: Text(
                j.error ?? 'başarısız',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ui(size: 10, color: c.red),
              ),
            ),
            Tooltip(
              message: 'Yeniden dene',
              child: IconButton(
                key: Key('retryJob_${j.id}'),
                icon: Icon(Icons.refresh, size: 13, color: c.amber),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                onPressed: () => widget.onRetryJob(j.id),
              ),
            ),
          ] else
            Text(
              rate != null && rate > 0
                  ? humanRate(rate)
                  : '${humanSize(j.bytes)}/${humanSize(j.size)}',
              style: context.mono(size: 10, color: c.textDim),
            ),
        ],
      ),
    );
  }

  static String _label(BatchView b) {
    if (b.scanning) return '${b.name} — Taranıyor…';
    final count = '${b.done}/${b.total} dosya';
    if (b.finished) {
      final parts = <String>['${b.done}/${b.total} başarılı'];
      if (b.failed > 0) parts.add('${b.failed} başarısız');
      if (b.cancelled > 0) parts.add('${b.cancelled} iptal');
      return '${b.name} — ${parts.join(', ')}';
    }
    return '${b.name} — $count';
  }
}
