import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/context_ext.dart';

/// One breadcrumb segment: its visible [label] and the absolute [path] that
/// clicking it navigates to. The last segment (current dir) is non-clickable.
class PathSegment {
  final String label;
  final String path;
  const PathSegment(this.label, this.path);
}

/// Splits an absolute-ish path into breadcrumb segments (D2). Pure + tested.
///
/// Handles three shapes the panes use:
/// - POSIX absolute (`/home/user/docs`) → `[/, home, user, docs]` with
///   cumulative paths (`/`, `/home`, `/home/user`, `/home/user/docs`).
/// - Remote relative (`.`, `./a/b`) → `[., a, b]` keeping the `.` root.
/// - Windows-ish local (`C:\a\b`) → split on `\` keeping the drive root.
///
/// The separator is auto-detected (`\` only when present and no `/` is), so the
/// same helper serves the local and remote panes without the caller passing a
/// flag.
List<PathSegment> breadcrumbSegments(String path) {
  if (path.isEmpty) return const [PathSegment('/', '/')];

  final useBackslash = path.contains('\\') && !path.contains('/');
  final sep = useBackslash ? '\\' : '/';

  // Relative remote root: "." or "./..."
  if (path == '.' || path.startsWith('./')) {
    final rest = path == '.' ? '' : path.substring(2);
    final out = <PathSegment>[const PathSegment('.', '.')];
    var acc = '.';
    for (final part in rest.split('/')) {
      if (part.isEmpty) continue;
      acc = '$acc/$part';
      out.add(PathSegment(part, acc));
    }
    return out;
  }

  final isAbsolutePosix = path.startsWith('/');
  final parts = path.split(sep).where((s) => s.isNotEmpty).toList();

  final out = <PathSegment>[];
  if (isAbsolutePosix) {
    out.add(const PathSegment('/', '/'));
    var acc = '';
    for (final part in parts) {
      acc = '$acc/$part';
      out.add(PathSegment(part, acc));
    }
  } else if (useBackslash) {
    // Windows: first part is the drive (e.g. "C:"). Keep it as the root.
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = i == 0 ? parts[i] : '$acc\\${parts[i]}';
      final label = i == 0 ? '${parts[i]}\\' : parts[i];
      out.add(PathSegment(label, acc));
    }
    if (out.isEmpty) out.add(PathSegment(path, path));
  } else {
    // Bare relative name(s) with no leading "./" — treat as-is.
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = i == 0 ? parts[i] : '$acc/${parts[i]}';
      out.add(PathSegment(parts[i], acc));
    }
    if (out.isEmpty) out.add(PathSegment(path, path));
  }
  return out;
}

/// Clickable breadcrumb path navigator (D2). Replaces the ellipsized path Text.
///
/// - Each ancestor segment is a button → [onNavigate] with its absolute path.
/// - The last segment (current dir) is bold and non-clickable.
/// - When the row would overflow, leading segments collapse into a leading
///   `…` popup menu; the tail (current dir) is NEVER truncated.
/// - A small pencil toggles a raw-path text field (Enter commits, Esc cancels).
/// - The full path shows on hover (tooltip).
class PathBreadcrumb extends StatefulWidget {
  final String path;
  final void Function(String absolutePath) onNavigate;

  const PathBreadcrumb({
    super.key,
    required this.path,
    required this.onNavigate,
  });

  @override
  State<PathBreadcrumb> createState() => _PathBreadcrumbState();
}

class _PathBreadcrumbState extends State<PathBreadcrumb> {
  bool _editing = false;
  late final TextEditingController _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    _ctrl.text = widget.path;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
    });
  }

  void _commitEdit() {
    final v = _ctrl.text.trim();
    setState(() => _editing = false);
    if (v.isNotEmpty && v != widget.path) widget.onNavigate(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_editing) {
      return SizedBox(
        height: 28,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() => _editing = false);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const Key('breadcrumbEdit'),
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            style: context.mono(size: 12, color: c.text),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.border),
              ),
            ),
            onSubmitted: (_) => _commitEdit(),
            onTapOutside: (_) => _commitEdit(),
          ),
        ),
      );
    }

    final segments = breadcrumbSegments(widget.path);
    return Tooltip(
      message: widget.path,
      waitDuration: const Duration(milliseconds: 600),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, cons) =>
                  _buildTrail(ctx, segments, cons.maxWidth, c),
            ),
          ),
          Tooltip(
            message: 'Yolu düzenle',
            child: IconButton(
              key: const Key('breadcrumbEditButton'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: Icon(Icons.edit_outlined, size: 13, color: c.textDim),
              onPressed: _startEdit,
            ),
          ),
        ],
      ),
    );
  }

  /// Lays the trail out right-to-left so the tail (current dir) is never cut;
  /// leading segments that do not fit collapse into a single `…` popup menu.
  Widget _buildTrail(
    BuildContext context,
    List<PathSegment> segments,
    double maxWidth,
    dynamic c,
  ) {
    // Decide how many leading segments to hide based on a coarse width budget.
    // (Exact text measurement is overkill; a per-segment estimate is enough and
    // keeps the widget pure-ish/testable.)
    const sepW = 12.0;
    const approxPerChar = 7.5;
    double widthOf(PathSegment s) => s.label.length * approxPerChar + 18;

    var hiddenCount = 0;
    while (true) {
      final visible = segments.sublist(hiddenCount);
      var total = hiddenCount > 0 ? (28 + sepW) : 0.0; // the "…" chip
      for (var i = 0; i < visible.length; i++) {
        total += widthOf(visible[i]);
        if (i < visible.length - 1) total += sepW;
      }
      // Always keep at least the last segment (and ideally one ancestor).
      if (total <= maxWidth || hiddenCount >= segments.length - 1) break;
      hiddenCount++;
    }

    final children = <Widget>[];
    if (hiddenCount > 0) {
      final hidden = segments.sublist(0, hiddenCount);
      children.add(
        PopupMenuButton<String>(
          key: const Key('breadcrumbOverflow'),
          tooltip: 'Üst klasörler',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_horiz, size: 16, color: c.textMuted),
          onSelected: widget.onNavigate,
          itemBuilder: (ctx) => [
            for (final s in hidden)
              PopupMenuItem(
                value: s.path,
                child: Text(s.label, style: context.mono(size: 12)),
              ),
          ],
        ),
      );
      children.add(_sep(context, c));
    }

    final visible = segments.sublist(hiddenCount);
    for (var i = 0; i < visible.length; i++) {
      final seg = visible[i];
      final isLast = i == visible.length - 1;
      if (isLast) {
        children.add(
          Flexible(
            child: Text(
              seg.label,
              key: const Key('breadcrumbCurrent'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mono(
                size: 12,
                weight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
        );
      } else {
        children.add(
          InkWell(
            key: Key('breadcrumbSeg_${seg.path}'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => widget.onNavigate(seg.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Text(
                seg.label,
                style: context.mono(size: 12, color: c.accent),
              ),
            ),
          ),
        );
        children.add(_sep(context, c));
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _sep(BuildContext context, dynamic c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Text('/', style: context.mono(size: 12, color: c.textDim)),
  );
}
