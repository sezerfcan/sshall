import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/remote_entry.dart';
import '../../services/sftp/remote_file_ops.dart';
import '../../services/sftp/remote_path.dart';
import '../../services/sftp/sftp_messages.dart';
import '../../services/sftp/transfer_plan.dart';
import '../../services/sftp/transfer_queue.dart';
import '../../services/sftp/transfer_rate_meter.dart';
import '../../theme/context_ext.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_text_field.dart';
import '../shell/resizable_split.dart';
import 'chmod_dialog.dart';
import 'edit_poller.dart';
import 'file_opener.dart';
import 'file_pane.dart';
import 'local_file_probe.dart';
import 'local_fs_controller.dart';
import 'overwrite_dialog.dart';
import 'overwrite_policy_dialog.dart';
import 'remote_edit_controller.dart';
import 'remote_edit_panel.dart';
import 'remote_edit_session.dart';
import 'sftp_help.dart';
import 'sftp_providers.dart';
import 'transfer_queue_panel.dart';

class SftpView extends ConsumerStatefulWidget {
  const SftpView({
    super.key,
    this.fileOpener = const UrlLauncherFileOpener(),
    this.localFileProbe = const IoLocalFileProbe(),
    this.editTempRoot,
  });

  /// Opens an edited local temp file in the OS default app (D3). Injectable for
  /// tests so the editor launch can be faked.
  final FileOpener fileOpener;

  /// Local-fs access used by the remote-edit controller (stat/ensure/delete
  /// temp dirs). Injectable for tests.
  final LocalFileProbe localFileProbe;

  /// Test seam: resolves the remote-edit temp root. Defaults to the app support
  /// dir (`<support>/remote-edits`) which has no platform channel under tests.
  final Future<String> Function()? editTempRoot;

  @override
  ConsumerState<SftpView> createState() => _SftpViewState();
}

class _SftpViewState extends ConsumerState<SftpView> {
  final _local = LocalFsController();
  String _localPath = '';
  String _remotePath = '.';
  List<FsEntry> _localEntries = [];
  List<FsEntry> _remoteEntries = [];
  bool _localLoading = false, _remoteLoading = false;
  String? _localError, _remoteError;
  TransferQueue? _queue;
  int _nextBatchId = 1;
  final _planner = TransferPlanner();
  // Plan-derived skip counts per batch, for the end-of-batch summary.
  final _batchSkips = <String, ({int existing, int symlink, int unsafe})>{};
  final _summarized = <String>{};
  StreamSubscription<SftpEvent>? _transfersSub;
  RemoteEditController? _edit;

  // ---- D1: resizable pane weights (persisted) ----
  static const _kPaneWeightsKey = 'sftpPaneWeights';
  static const double _kMinPaneWidth = 240;
  List<double> _paneWeights = const [0.5, 0.5];

  // ---- D3: per-pane sort (persisted) ----
  static const _kLocalSortKey = 'sftpLocalSort';
  static const _kRemoteSortKey = 'sftpRemoteSort';
  SortColumn _localSortCol = SortColumn.name;
  bool _localSortAsc = true;
  SortColumn _remoteSortCol = SortColumn.name;
  bool _remoteSortAsc = true;

  // ---- D4: per-pane selection (by entry name; stable across re-sorts) ----
  final Set<String> _localSel = {};
  final Set<String> _remoteSel = {};
  int _localAnchor = -1;
  int _remoteAnchor = -1;

  // ---- D7: per-job rate meters + queue-panel collapse + auto-clear timers ----
  final Map<int, TransferRateMeter> _meters = {};
  bool _queueCollapsed = false;
  final Map<String, Timer> _autoClear = {};

  /// Default remote-edit temp root: `<app support>/remote-edits`. Overridable
  /// via [SftpView.editTempRoot] in tests (path_provider has no channel there).
  Future<String> _defaultEditTempRoot() async {
    final base = await getApplicationSupportDirectory();
    return p.join(base.path, 'remote-edits');
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _transfersSub?.cancel();
    _edit?.dispose();
    for (final t in _autoClear.values) {
      t.cancel();
    }
    _meters.clear();
    super.dispose();
  }

  /// Restore persisted pane weights + per-pane sort (D1/D3). Best-effort: a
  /// missing prefs override (e.g. in widget tests) or any malformed value falls
  /// back to the default.
  void _loadPrefs() {
    final SharedPreferences prefs;
    try {
      prefs = ref.read(sharedPrefsProvider);
    } catch (_) {
      return; // no prefs available (test harness) — keep defaults
    }
    final w = prefs.getStringList(_kPaneWeightsKey);
    if (w != null && w.length == 2) {
      final a = double.tryParse(w[0]);
      final b = double.tryParse(w[1]);
      if (a != null && b != null && a > 0 && b > 0) {
        final sum = a + b;
        _paneWeights = [a / sum, b / sum];
      }
    }
    final local = _readSort(prefs, _kLocalSortKey);
    _localSortCol = local.$1;
    _localSortAsc = local.$2;
    final remote = _readSort(prefs, _kRemoteSortKey);
    _remoteSortCol = remote.$1;
    _remoteSortAsc = remote.$2;
  }

  (SortColumn, bool) _readSort(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw != null) {
      final parts = raw.split(':');
      for (final col in SortColumn.values) {
        if (col.name == parts.first) {
          return (col, parts.length < 2 || parts[1] == 'asc');
        }
      }
    }
    return (SortColumn.name, true);
  }

  SharedPreferences? get _prefsOrNull {
    try {
      return ref.read(sharedPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  void _persistWeights(List<double> w) {
    _prefsOrNull?.setStringList(_kPaneWeightsKey, [
      w[0].toString(),
      w[1].toString(),
    ]);
  }

  void _persistSort(String key, SortColumn col, bool asc) {
    _prefsOrNull?.setString(key, '${col.name}:${asc ? 'asc' : 'desc'}');
  }

  /// Toggle/apply a sort column for a pane (D3): clicking the active column
  /// flips direction, a new column sorts ascending. Persists per pane.
  void _onSort(bool remote, SortColumn col) {
    setState(() {
      if (remote) {
        if (_remoteSortCol == col) {
          _remoteSortAsc = !_remoteSortAsc;
        } else {
          _remoteSortCol = col;
          _remoteSortAsc = true;
        }
        _persistSort(_kRemoteSortKey, _remoteSortCol, _remoteSortAsc);
      } else {
        if (_localSortCol == col) {
          _localSortAsc = !_localSortAsc;
        } else {
          _localSortCol = col;
          _localSortAsc = true;
        }
        _persistSort(_kLocalSortKey, _localSortCol, _localSortAsc);
      }
    });
  }

  /// Apply a click-selection to a pane's selection set (D4). Pure model: plain
  /// click = single select (sets anchor); shift = anchor→index range; meta =
  /// toggle the clicked index (anchor unchanged).
  void _onSelect(
    bool remote,
    int index, {
    required bool shift,
    required bool meta,
  }) {
    final sorted = remote ? _sortedRemote() : _sortedLocal();
    if (index < 0 || index >= sorted.length) return;
    final sel = remote ? _remoteSel : _localSel;
    final anchor = remote ? _remoteAnchor : _localAnchor;
    setState(() {
      if (shift && anchor >= 0 && anchor < sorted.length) {
        sel.clear();
        final lo = anchor < index ? anchor : index;
        final hi = anchor < index ? index : anchor;
        for (var i = lo; i <= hi; i++) {
          sel.add(sorted[i].name);
        }
      } else if (meta) {
        final name = sorted[index].name;
        if (!sel.add(name)) sel.remove(name);
        if (remote) {
          _remoteAnchor = index;
        } else {
          _localAnchor = index;
        }
      } else {
        sel
          ..clear()
          ..add(sorted[index].name);
        if (remote) {
          _remoteAnchor = index;
        } else {
          _localAnchor = index;
        }
      }
    });
  }

  List<FsEntry> _sortedLocal() =>
      sortEntries(_localEntries, _localSortCol, _localSortAsc);
  List<FsEntry> _sortedRemote() =>
      sortEntries(_remoteEntries, _remoteSortCol, _remoteSortAsc);

  /// The entries to operate on for an inline/menu action: the full selection if
  /// the acted-on entry is part of a multi-selection, else just that entry.
  List<FsEntry> _effectiveTargets(bool remote, FsEntry e) {
    final sel = remote ? _remoteSel : _localSel;
    if (sel.contains(e.name) && sel.length > 1) {
      final sorted = remote ? _sortedRemote() : _sortedLocal();
      return sorted.where((x) => sel.contains(x.name)).toList();
    }
    return [e];
  }

  Future<void> _bootstrap() async {
    // Default to an always-accessible root under the macOS App Sandbox (ADR
    // 0023): prefer the real ~/Downloads (granted via the downloads
    // entitlement), then fall back to the sandbox container Documents dir.
    // Either avoids a PathAccessException at startup; the user can grant other
    // folders via "Klasör seç".
    String? start;
    try {
      start = (await getDownloadsDirectory())?.path;
    } catch (_) {
      /* not available on this platform */
    }
    if (start == null) {
      try {
        start = (await getApplicationDocumentsDirectory()).path;
      } catch (e) {
        if (mounted) setState(() => _localError = e.toString());
      }
    }
    if (start != null) {
      _localPath = start;
      await _refreshLocal();
    }
    final session = ref.read(sftpSessionProvider);
    if (session != null) _attachSession(session);
  }

  /// Wires the view to [session]: cancels any prior transfers subscription,
  /// resets per-session UI state, re-subscribes to [RemoteFileOps.transfers],
  /// and loads the remote root. Runs both at first mount (if a session already
  /// exists) and whenever the active session changes. Backend-agnostic (ADR
  /// 0028): [session] is any [RemoteFileOps] — a real SFTP session or a Docker
  /// file backend — and the body uses only RemoteFileOps members.
  void _attachSession(RemoteFileOps session) {
    _transfersSub?.cancel();
    // The previous session (if any) is being replaced: its in-flight edits can
    // no longer upload, so flush them to the user (keeps the local copy) and
    // dispose the old controller before wiring the new one.
    _edit?.onSftpClosed();
    _edit?.dispose();
    setState(() {
      _queue = TransferQueue(
        start: (job) => job.kind == TransferKind.upload
            ? session.startUpload(job.srcPath, job.destPath)
            : session.startDownload(job.srcPath, job.destPath),
        cancel: session.cancel,
      );
      // Per-session remote-edit controller (D3). All seams delegate to the
      // captured [session]; onChanged re-renders the panel.
      _edit = RemoteEditController(
        startDownload: (r, l) => session.startDownload(r, l),
        startUpload: (l, r) => session.startUpload(l, r),
        stat: session.stat,
        chmod: session.chmod,
        fileOpener: widget.fileOpener,
        poller: TimerEditPoller(),
        probe: widget.localFileProbe,
        tempRootPath: widget.editTempRoot ?? _defaultEditTempRoot,
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
      // New session: the old queue (and its job ids) is replaced, so drop every
      // stale per-job rate meter (D7 memory hygiene).
      _meters.clear();
      _batchSkips.clear();
      _summarized.clear();
      _remotePath = '.';
      _remoteEntries = [];
    });
    // Best-effort cleanup of temp dirs left by a prior crash (no live sessions).
    _edit?.sweepStaleTempDirs();
    _transfersSub = session.transfers.listen(_onTransfer);
    _refreshRemote();
  }

  final _transferClock = Stopwatch()..start();

  void _onTransfer(SftpEvent e) {
    final q = _queue;
    if (q == null) return;
    final isTerminal = e is TransferDone || e is TransferFailed;
    if (e is! TransferProgress && !isTerminal) return; // not a transfer event
    q.onEvent(e);
    // Feed per-job rate meters (D7) from the same progress samples, keyed by the
    // queue's internal job id so the panel can read speed/ETA per file.
    if (e is TransferProgress) {
      final job = q.jobByTransferId(e.transferId);
      if (job != null) {
        final m = _meters.putIfAbsent(job.id, () => TransferRateMeter());
        m.sample(e.bytes, at: _transferClock.elapsed);
      }
    }
    // Same broadcast events feed both the queue and the edit controller; each
    // handles only its own transferIds (edit downloads/uploads vs. queue jobs).
    _edit?.onTransferEvent(e);
    setState(() {});
    if (isTerminal) {
      _refreshLocal();
      _refreshRemote();
      _maybeSummarize();
      _scheduleAutoClear();
    }
  }

  /// Prunes rate-meter entries whose job no longer exists in the queue (D7
  /// memory hygiene): after a batch is dismissed/cleared/auto-cleared its jobs
  /// are gone, so their meters would otherwise leak for the view's lifetime.
  /// Reconciles against the live job ids regardless of which path removed the
  /// batch, so it is correct even when called after the batch is already gone.
  void _pruneMeters() {
    final q = _queue;
    if (q == null) {
      _meters.clear();
      return;
    }
    final live = <int>{
      for (final b in q.batches)
        for (final j in q.jobsFor(b.id)) j.id,
    };
    _meters.removeWhere((id, _) => !live.contains(id));
  }

  /// Test seam: number of live per-job rate meters retained by the view.
  @visibleForTesting
  int get meterCount => _meters.length;

  /// Auto-clear succeeded batches after a brief settle (D7): a batch with no
  /// failed/cancelled jobs is dismissed ~4s after it finishes. Failed batches
  /// stay so the user can read the reason + retry.
  void _scheduleAutoClear() {
    final q = _queue;
    if (q == null) return;
    for (final b in q.batches) {
      if (!b.finished || b.failed > 0 || b.cancelled > 0) continue;
      if (_autoClear.containsKey(b.id)) continue;
      _autoClear[b.id] = Timer(const Duration(seconds: 4), () {
        _autoClear.remove(b.id);
        if (!mounted) return;
        setState(() {
          _queue?.dismissBatch(b.id);
          _pruneMeters();
        });
      });
    }
  }

  /// Shows a one-time summary SnackBar for each batch that just finished.
  void _maybeSummarize() {
    final q = _queue;
    if (q == null) return;
    for (final b in q.batches) {
      if (!b.finished || _summarized.contains(b.id)) continue;
      _summarized.add(b.id);
      final skips = _batchSkips[b.id];
      final parts = <String>['${b.done}/${b.total} başarılı'];
      if (b.failed > 0) parts.add('${b.failed} başarısız');
      final skipped =
          (skips?.existing ?? 0) +
          (skips?.symlink ?? 0) +
          (skips?.unsafe ?? 0) +
          b.cancelled;
      if (skipped > 0) parts.add('$skipped atlandı');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${b.name}: ${parts.join(', ')}')),
        );
      }
    }
  }

  Future<void> _refreshLocal() async {
    setState(() => _localLoading = true);
    try {
      final entries = await _local.list(_localPath);
      setState(() {
        _localEntries = entries;
        _localError = null;
      });
    } on PathAccessException {
      setState(() => _localError = _accessDeniedMsg(_localPath));
    } catch (e) {
      setState(() => _localError = e.toString());
    } finally {
      setState(() => _localLoading = false);
    }
  }

  /// Friendly message for a sandbox-denied path (ADR 0023). The pane pairs this
  /// with a "Klasör seç" action so the user can grant access.
  String _accessDeniedMsg(String path) =>
      '“${p.basename(path)}” klasörüne erişim izni yok (macOS güvenlik kutusu). '
      '“Klasör seç” ile erişmek istediğin klasöre izin verebilirsin.';

  /// Navigate the local pane to [target], guarding against the macOS App Sandbox
  /// (ADR 0023): if the destination is not accessible we DON'T strand the user
  /// there — we revert to the last accessible path and show a message + the
  /// "Klasör seç" action. Used by "up" and "open folder".
  Future<void> _navigateLocal(String target) async {
    final prev = _localPath;
    setState(() => _localLoading = true);
    try {
      final entries = await _local.list(target);
      setState(() {
        _localPath = target;
        _localEntries = entries;
        _localError = null;
      });
    } on PathAccessException {
      setState(() {
        _localPath = prev; // stay where we were
        _localError = _accessDeniedMsg(target);
      });
    } catch (e) {
      setState(() {
        _localPath = prev;
        _localError = e.toString();
      });
    } finally {
      setState(() => _localLoading = false);
    }
  }

  /// Let the user grant access to a folder via the OS picker. On macOS this
  /// opens an NSOpenPanel, which gives the sandbox security-scoped access to the
  /// chosen directory (ADR 0023). The chosen folder becomes the new local root.
  Future<void> _pickLocalRoot() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Yerel kök klasör seç',
      );
      if (dir == null) return; // cancelled
      await _navigateLocal(dir);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Klasör seçilemedi: $e')));
      }
    }
  }

  Future<void> _refreshRemote() async {
    final session = ref.read(sftpSessionProvider);
    if (session == null) return;
    setState(() => _remoteLoading = true);
    try {
      final entries = await session.list(_remotePath);
      setState(() {
        _remoteEntries = entries;
        _remoteError = null;
      });
    } catch (e) {
      setState(() => _remoteError = e.toString());
    } finally {
      setState(() => _remoteLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // SftpView is eager-built in the AppShell IndexedStack before any host is
    // selected, so the session is null at mount; re-wire whenever it changes.
    ref.listen<RemoteFileOps?>(sftpSessionProvider, (prev, next) {
      if (next != null && !identical(prev, next)) _attachSession(next);
    });
    final session = ref.watch(sftpSessionProvider);
    final host = ref.watch(sftpHostProvider);
    final c = context.c;
    if (session == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_alt, size: 40, color: c.textDim),
            const SizedBox(height: 12),
            Text(
              'Bağlantılar’dan bir host seçip SFTP açın',
              style: context.ui(size: 14, color: c.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'Bir sunucuya bağlanıp dosyalarını buradan aktarabilirsin.',
              style: context.ui(size: 12, color: c.textDim),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 16, color: c.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(host ?? 'SFTP', style: context.ui(size: 13)),
              ),
              Tooltip(
                message: 'SFTP yardımı',
                child: IconButton(
                  key: const Key('sftpHelpButton'),
                  icon: Icon(Icons.help_outline, size: 16, color: c.textMuted),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showSftpHelpDialog(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ResizableSplit(
              axis: Axis.horizontal,
              weights: _paneWeights,
              onWeights: (w) {
                setState(() => _paneWeights = w);
                _persistWeights(w);
              },
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: _kMinPaneWidth),
                  child: _localPane(),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: _kMinPaneWidth),
                  child: _remotePane(),
                ),
              ],
            ),
          ),
        ),
        RemoteEditPanel(
          sessions: _edit?.sessions ?? const [],
          onFinish: (id) => _edit?.finish(id),
          onResolve: _editResolve,
        ),
        TransferQueuePanel(
          batches: _queue?.batches ?? const [],
          collapsed: _queueCollapsed,
          onToggleCollapse: () =>
              setState(() => _queueCollapsed = !_queueCollapsed),
          jobsFor: (id) => _queue?.jobsFor(id) ?? const [],
          rateFor: _rateForJob,
          onCancelBatch: (id) => setState(() => _queue?.cancelBatch(id)),
          onDismissBatch: (id) => setState(() {
            _queue?.dismissBatch(id);
            _pruneMeters();
          }),
          onClearFinished: () => setState(() {
            _queue?.clearFinished();
            _pruneMeters();
          }),
          onRetryBatch: (id) => setState(() => _queue?.retryFailedBatch(id)),
          onRetryJob: (id) => setState(() => _queue?.retryJob(id)),
        ),
      ],
    );
  }

  /// Smoothed speed for an active job from its rate meter (D7). Null when there
  /// is no meter yet or the job isn't active.
  double? _rateForJob(int jobId) => _meters[jobId]?.bytesPerSec;

  FilePane _localPane() => FilePane(
    title: 'YEREL',
    path: _localPath,
    entries: _localEntries,
    loading: _localLoading,
    error: _localError,
    isRemote: false,
    onChooseRoot: _pickLocalRoot,
    onNavigate: _navigateLocal,
    sortColumn: _localSortCol,
    sortAscending: _localSortAsc,
    onSort: (col) => _onSort(false, col),
    selectedNames: _localSel,
    onSelect: (i, {shift = false, meta = false}) =>
        _onSelect(false, i, shift: shift, meta: meta),
    onActivate: (e) {
      if (e.isDir) {
        _navigateLocal((e as LocalEntry).path);
      } else {
        _transferEntry(e, upload: true);
      }
    },
    onTransferSelection: (e) => _transferTargets(false, e),
    onDeleteSelection: (e) => _deleteTargets(false, e),
    onDropEntries: (data, {targetDir}) => _onDrop(data, targetDir: targetDir),
    onUp: () => _navigateLocal(p.dirname(_localPath)),
    onRefresh: _refreshLocal,
    actions: FilePaneActions(
      onOpen: (e) {
        if (e.isDir) _navigateLocal((e as LocalEntry).path);
      },
      onTransfer: (e) => _transferEntry(e, upload: true), // local -> remote
      onRename: (e) => _renameLocal(e as LocalEntry),
      onDelete: (e) => _deleteLocal(e as LocalEntry),
      onMkdir: _mkdirLocal,
      onCopyPath: (e) => _copyPath((e as LocalEntry).path),
    ),
  );

  FilePane _remotePane() => FilePane(
    title: 'UZAK',
    path: _remotePath,
    entries: _remoteEntries,
    loading: _remoteLoading,
    error: _remoteError,
    isRemote: true,
    onNavigate: (target) {
      setState(() => _remotePath = target);
      _refreshRemote();
    },
    sortColumn: _remoteSortCol,
    sortAscending: _remoteSortAsc,
    onSort: (col) => _onSort(true, col),
    selectedNames: _remoteSel,
    onSelect: (i, {shift = false, meta = false}) =>
        _onSelect(true, i, shift: shift, meta: meta),
    onActivate: (e) {
      if (e.isDir) {
        setState(() => _remotePath = (e as RemoteEntry).path);
        _refreshRemote();
      } else {
        _transferEntry(e, upload: false);
      }
    },
    onTransferSelection: (e) => _transferTargets(true, e),
    onDeleteSelection: (e) => _deleteTargets(true, e),
    onDropEntries: (data, {targetDir}) => _onDrop(data, targetDir: targetDir),
    onUp: () {
      setState(() => _remotePath = RemotePath.parent(_remotePath));
      _refreshRemote();
    },
    onRefresh: _refreshRemote,
    actions: FilePaneActions(
      onOpen: (e) {
        if (e.isDir) {
          setState(() => _remotePath = (e as RemoteEntry).path);
          _refreshRemote();
        }
      },
      onTransfer: (e) => _transferEntry(e, upload: false), // remote -> local
      onRename: (e) => _renameRemote(e as RemoteEntry),
      onDelete: (e) => _deleteRemote(e as RemoteEntry),
      onMkdir: _mkdirRemote,
      onChmod: (e) => _chmodRemote(e as RemoteEntry),
      onEdit: (e) => _editRemote(e as RemoteEntry),
      onCopyPath: (e) => _copyPath((e as RemoteEntry).path),
    ),
  );

  /// Transfer every effective target (full selection if [e] is part of a
  /// multi-selection) to the other pane (D4 fan-out).
  void _transferTargets(bool remote, FsEntry e) {
    for (final t in _effectiveTargets(remote, e)) {
      _transferEntry(t, upload: !remote);
    }
  }

  /// Delete every effective target (full selection fan-out).
  Future<void> _deleteTargets(bool remote, FsEntry e) async {
    final targets = _effectiveTargets(remote, e);
    if (targets.isEmpty) return;
    final msg = targets.length == 1
        ? '"${targets.first.name}" silinsin mi?'
        : '${targets.length} öğe silinsin mi?';
    if (!await _confirm(msg)) return;
    for (final t in targets) {
      if (remote) {
        await _guardRemote(
          () => ref
              .read(sftpSessionProvider)!
              .remove((t as RemoteEntry).path, isDir: t.isDir),
        );
      } else {
        await _guardLocal(
          () => _local.delete((t as LocalEntry).path, isDir: t.isDir),
        );
      }
    }
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yol kopyalandı: $path')));
    }
  }

  /// Handle an in-app drop (D5): direction comes from the payload's source pane
  /// (remote source = download, local source = upload). [targetDir] overrides
  /// the destination directory when dropped onto a folder row.
  void _onDrop(FileDragData data, {String? targetDir}) {
    final upload = !data.fromRemote;
    for (final e in data.entries) {
      _transferEntry(e, upload: upload, destDirOverride: targetDir);
    }
  }

  // ---- remote-edit actions (D3) ----
  static const int _bigFileThreshold = 5 * 1024 * 1024;

  /// "Düzenle" on a remote file: confirm if the file is large (it must be
  /// downloaded and watched), then hand off to the controller.
  Future<void> _editRemote(RemoteEntry e) async {
    final edit = _edit;
    if (edit == null) return;
    if (e.size > _bigFileThreshold) {
      final ok = await _confirmBig(e.name, e.size);
      if (!ok) return;
    }
    await edit.startEdit(e);
  }

  Future<bool> _confirmBig(String name, int size) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          '“$name” büyük bir dosya (${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Düzenlemek için indirilip izlenecek. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aç'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Wraps the controller's conflict resolution; on "save as local" it tells
  /// the user where the preserved copy lives.
  Future<void> _editResolve(String id, ConflictChoice choice) async {
    final edit = _edit;
    if (edit == null) return;
    // Capture the temp path before resolving (the session may change state).
    String? tempPath;
    for (final s in edit.sessions) {
      if (s.id == id) {
        tempPath = s.localTempPath;
        break;
      }
    }
    await edit.resolveConflict(id, choice);
    if (choice == ConflictChoice.saveAsLocal && tempPath != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yerel kopya korundu: $tempPath')));
    }
  }

  /// Validates a single path segment (mkdir/rename/transfer name) against
  /// traversal: rejects empty, `.`/`..`, anything with a `/` or `\`, and
  /// control characters. On rejection shows an inline error and returns null,
  /// so callers can `if ((name = _safeName(...)) == null) return;`. Centralizes
  /// the guard so every user- or server-supplied name passes through it before
  /// being joined onto the current directory.
  String? _safeName(String? name) {
    if (name == null) return null;
    if (!RemotePath.isSafeSegment(name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geçersiz ad: tek bir dosya/klasör adı olmalı '
              '("/", "\\", ".", ".." ve boşluk-yalnız ad kullanılamaz).',
            ),
          ),
        );
      }
      return null;
    }
    return name;
  }

  // ---- transfer actions ----
  /// Entry point for the pane "Diğer panele aktar" action. [upload] = local→
  /// remote (local pane), else remote→local. Routes single files through the
  /// existing per-file overwrite dialog and folders through the recursive
  /// planner + queue (D2).
  Future<void> _transferEntry(
    FsEntry e, {
    required bool upload,
    String? destDirOverride,
  }) async {
    if (e.isDir) {
      await _transferFolder(
        e,
        upload: upload,
        destDirOverride: destDirOverride,
      );
    } else {
      await _transferFile(e, upload: upload, destDirOverride: destDirOverride);
    }
  }

  Future<void> _transferFile(
    FsEntry e, {
    required bool upload,
    String? destDirOverride,
  }) async {
    final safe = _safeName(e.name);
    if (safe == null) return;
    var name = safe;
    final session = ref.read(sftpSessionProvider)!;
    final q = _queue;
    if (q == null) return;
    // The destination directory: the other pane's current dir, unless a folder
    // drop targeted a specific folder (D5).
    final remoteDestDir = destDirOverride ?? _remotePath;
    final localDestDir = destDirOverride ?? _localPath;
    final String src, dest;
    if (upload) {
      src = (e as LocalEntry).path;
      final remoteDest = RemotePath.join(remoteDestDir, name);
      if (await session.stat(remoteDest) != null) {
        if (!mounted) return;
        final choice = await showOverwriteDialog(context, name);
        if (choice == null || choice == OverwriteChoice.skip) return;
        if (choice == OverwriteChoice.keepBoth) {
          final taken = _remoteEntries.map((x) => x.name).toSet();
          name = uniqueName(name, taken.contains);
        }
      }
      dest = RemotePath.join(remoteDestDir, name);
    } else {
      src = (e as RemoteEntry).path;
      final localDest = _local.join(localDestDir, name);
      if (await _local.exists(localDest)) {
        if (!mounted) return;
        final choice = await showOverwriteDialog(context, name);
        if (choice == null || choice == OverwriteChoice.skip) return;
        if (choice == OverwriteChoice.keepBoth) {
          name = uniqueName(
            name,
            (n) => File(_local.join(localDestDir, n)).existsSync(),
          );
        }
      }
      dest = _local.join(localDestDir, name);
    }
    final batchId = 'b${_nextBatchId++}';
    setState(
      () => q.enqueueBatch(
        batchId,
        name,
        upload ? TransferKind.upload : TransferKind.download,
        [
          FileJob(
            srcPath: src,
            destPath: dest,
            name: name,
            size: e.size,
            destExists: false,
          ),
        ],
      ),
    );
  }

  Future<void> _transferFolder(
    FsEntry e, {
    required bool upload,
    String? destDirOverride,
  }) async {
    final safe = _safeName(e.name);
    if (safe == null) return;
    final session = ref.read(sftpSessionProvider)!;
    final q = _queue;
    if (q == null) return;

    final policy = await showOverwritePolicyDialog(context, safe);
    if (policy == null) return; // cancelled

    final batchId = 'b${_nextBatchId++}';
    setState(() => q.beginBatch(batchId, safe)); // scanning…

    final TransferPlan plan;
    try {
      if (upload) {
        plan = await _planner.plan(
          root: _node(e as LocalEntry),
          destDir: destDirOverride ?? _remotePath,
          listDir: (path) async =>
              (await _local.list(path)).map(_node).toList(),
          destExists: (dp) async => await session.stat(dp) != null,
          joinDest: RemotePath.join,
          isSafeSegment: RemotePath.isSafeSegment,
          policy: policy,
        );
      } else {
        plan = await _planner.plan(
          root: _node(e as RemoteEntry),
          destDir: destDirOverride ?? _localPath,
          listDir: (path) async =>
              (await session.list(path)).map(_node).toList(),
          destExists: (dp) async => _local.exists(dp),
          joinDest: _local.join,
          isSafeSegment: RemotePath.isSafeSegment,
          policy: policy,
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tarama hatası: $err')));
      }
      setState(() => q.dismissBatch(batchId));
      return;
    }

    // Create the destination dir skeleton (parent-before-child). Existing dirs
    // are tolerated: local create() is a no-op, remote "already exists" is
    // swallowed.
    for (final d in plan.dirs) {
      if (upload) {
        await session.mkdir(d).catchError((_) {});
      } else {
        await _local.mkdir(d).catchError((_) {});
      }
    }

    // askEach: resolve conflicts up front (sequential), dropping skipped files.
    final files = <FileJob>[];
    for (final f in plan.files) {
      if (policy == OverwritePolicy.askEach && f.destExists) {
        if (!mounted) return;
        final choice = await showOverwriteDialog(context, f.name);
        if (choice == null || choice == OverwriteChoice.skip) continue;
        // keepBoth on a tree would change the dest path; D2 keeps it simple and
        // overwrites on "keepBoth" too (documented limitation).
      }
      files.add(f);
    }

    _batchSkips[batchId] = (
      existing: plan.skippedExisting,
      symlink: plan.skippedSymlink,
      unsafe: plan.skippedUnsafe,
    );
    setState(
      () => q.enqueueBatch(
        batchId,
        safe,
        upload ? TransferKind.upload : TransferKind.download,
        files,
      ),
    );
  }

  /// Normalizes a pane entry into a planner [FsNode] (needs the concrete path).
  FsNode _node(FsEntry e) => FsNode(
    name: e.name,
    path: e is LocalEntry ? e.path : (e as RemoteEntry).path,
    isDir: e.isDir,
    isSymlink: e.isSymlink,
    size: e.size,
  );

  // ---- ops: prompts then call session/_local, then refresh ----
  Future<void> _mkdirRemote() async {
    final name = _safeName(await _prompt('Yeni klasör adı'));
    if (name == null) return;
    await _guardRemote(
      () => ref
          .read(sftpSessionProvider)!
          .mkdir(RemotePath.join(_remotePath, name)),
    );
  }

  Future<void> _renameRemote(RemoteEntry e) async {
    final raw = await _prompt('Yeni ad', initial: e.name);
    if (raw == null || raw == e.name) return;
    final name = _safeName(raw);
    if (name == null) return;
    await _guardRemote(
      () => ref
          .read(sftpSessionProvider)!
          .rename(e.path, RemotePath.join(_remotePath, name)),
    );
  }

  Future<void> _deleteRemote(RemoteEntry e) async {
    if (!await _confirm('"${e.name}" silinsin mi?')) return;
    await _guardRemote(
      () => ref.read(sftpSessionProvider)!.remove(e.path, isDir: e.isDir),
    );
  }

  Future<void> _chmodRemote(RemoteEntry e) async {
    final mode = await showChmodDialog(
      context,
      name: e.name,
      mode: e.mode ?? 0,
    );
    if (mode == null) return;
    await _guardRemote(
      () => ref.read(sftpSessionProvider)!.chmod(e.path, mode),
    );
  }

  Future<void> _mkdirLocal() async {
    final name = _safeName(await _prompt('Yeni klasör adı'));
    if (name == null) return;
    await _guardLocal(() => _local.mkdir(_local.join(_localPath, name)));
  }

  Future<void> _renameLocal(LocalEntry e) async {
    final raw = await _prompt('Yeni ad', initial: e.name);
    if (raw == null || raw == e.name) return;
    final name = _safeName(raw);
    if (name == null) return;
    await _guardLocal(
      () => _local.rename(e.path, _local.join(_localPath, name)),
    );
  }

  Future<void> _deleteLocal(LocalEntry e) async {
    if (!await _confirm('"${e.name}" silinsin mi?')) return;
    await _guardLocal(() => _local.delete(e.path, isDir: e.isDir));
  }

  Future<void> _guardRemote(Future<void> Function() op) async {
    try {
      await op();
      await _refreshRemote();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Runs a local filesystem mutation, then refreshes. A sandbox denial (ADR
  /// 0023) is surfaced as a friendly SnackBar instead of leaking as an
  /// unhandled exception.
  Future<void> _guardLocal(Future<void> Function() op) async {
    try {
      await op();
      await _refreshLocal();
    } on PathAccessException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accessDeniedMsg(_localPath))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<String?> _prompt(String title, {String? initial}) {
    final ctrl = TextEditingController(text: initial ?? '');
    // Hoisted outside the StatefulBuilder so it survives rebuilds.
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Validate on confirm: an empty name no longer closes the dialog
          // silently (UX Top-3 #2). Instead it shows an inline, field-scoped
          // error so the user understands why nothing happened.
          void confirm() {
            final name = ctrl.text.trim();
            if (name.isEmpty) {
              setLocal(() => error = 'Ad boş olamaz');
              return;
            }
            Navigator.pop(ctx, name);
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 320,
              // Uses the shared AppTextField (label + hint + inline errorText)
              // for a consistent look with the rest of the app.
              child: AppTextField(
                controller: ctrl,
                label: title,
                hintText: 'örn. yedekler',
                errorText: error,
                autofocus: true,
                onChanged: (_) {
                  if (error != null) setLocal(() => error = null);
                },
                onSubmitted: (_) => confirm(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              TextButton(onPressed: confirm, child: const Text('Tamam')),
            ],
          );
        },
      ),
    ).whenComplete(() {
      // Dispose after the dialog route has finished its exit transition, so the
      // controller is no longer attached to a TextField that is still being
      // rebuilt during the pop animation.
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    });
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
