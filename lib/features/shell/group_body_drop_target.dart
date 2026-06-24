import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import 'shell_state.dart';
import 'split_tree.dart';

/// Which [DropZone] a local pointer position falls into within a group body
/// (full-area directional drop, ADR 0019). The central box `[0.35,0.65]²` is the
/// "move into group" zone; everywhere else snaps to the nearest edge. Pure so it
/// can be unit-tested.
DropZone zoneFor(Size size, Offset local) {
  if (size.width <= 0 || size.height <= 0) return DropZone.center;
  final fx = (local.dx / size.width).clamp(0.0, 1.0);
  final fy = (local.dy / size.height).clamp(0.0, 1.0);
  const lo = 0.35, hi = 0.65;
  if (fx >= lo && fx <= hi && fy >= lo && fy <= hi) return DropZone.center;
  final dl = fx, dr = 1 - fx, dt = fy, db = 1 - fy;
  final m = [dl, dr, dt, db].reduce((a, b) => a < b ? a : b);
  if (m == dl) return DropZone.left;
  if (m == dr) return DropZone.right;
  if (m == dt) return DropZone.top;
  return DropZone.bottom;
}

String _labelFor(DropZone z) => switch (z) {
  DropZone.left => 'Sola böl',
  DropZone.right => 'Sağa böl',
  DropZone.top => 'Yukarı böl',
  DropZone.bottom => 'Aşağı böl',
  DropZone.center => 'Bu gruba taşı',
};

IconData _iconFor(DropZone z) => switch (z) {
  DropZone.left => Icons.border_left,
  DropZone.right => Icons.border_right,
  DropZone.top => Icons.border_top,
  DropZone.bottom => Icons.border_bottom,
  DropZone.center => Icons.input,
};

/// Wraps a group's body. While a tab drag is in flight ([dragActive]) it overlays
/// a full-area, five-zone [DragTarget] that shows a live preview of where the
/// drop will land and reports the chosen [DropZone] via [onDrop]. When no drag is
/// active it is transparent (just the [child]) so normal interaction is intact.
class GroupBodyDropTarget extends StatefulWidget {
  final String groupId;
  final bool dragActive;
  final void Function(TabDragData data, DropZone zone) onDrop;
  final Widget child;

  const GroupBodyDropTarget({
    super.key,
    required this.groupId,
    required this.dragActive,
    required this.onDrop,
    required this.child,
  });

  @override
  State<GroupBodyDropTarget> createState() => _GroupBodyDropTargetState();
}

class _GroupBodyDropTargetState extends State<GroupBodyDropTarget> {
  final GlobalKey _boxKey = GlobalKey();
  DropZone? _zone;

  DropZone? _zoneAt(Offset globalPos) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return zoneFor(box.size, box.globalToLocal(globalPos));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.dragActive) return widget.child;
    return Stack(
      key: _boxKey,
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: DragTarget<TabDragData>(
            onMove: (d) {
              final z = _zoneAt(d.offset);
              if (z != _zone) setState(() => _zone = z);
            },
            onLeave: (_) {
              if (_zone != null) setState(() => _zone = null);
            },
            onAcceptWithDetails: (d) {
              final z = _zoneAt(d.offset) ?? DropZone.center;
              widget.onDrop(d.data, z);
              setState(() => _zone = null);
            },
            builder: (context, cand, rej) =>
                _zone == null ? const SizedBox.expand() : _preview(_zone!),
          ),
        ),
      ],
    );
  }

  Widget _preview(DropZone zone) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth, h = cons.maxHeight;
        final rect = switch (zone) {
          DropZone.left => Rect.fromLTWH(0, 0, w / 2, h),
          DropZone.right => Rect.fromLTWH(w / 2, 0, w / 2, h),
          DropZone.top => Rect.fromLTWH(0, 0, w, h / 2),
          DropZone.bottom => Rect.fromLTWH(0, h / 2, w, h / 2),
          DropZone.center => Rect.fromLTWH(0, 0, w, h),
        };
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Container(
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  border: Border.all(color: c.accent, width: 2),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(zone), size: 24, color: c.accent),
                      const SizedBox(height: 6),
                      Text(
                        _labelFor(zone),
                        style: context.ui(
                          size: 13,
                          weight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
