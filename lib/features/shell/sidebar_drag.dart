/// Pure drag-and-drop data + zone math for the connection tree (ADR 0035 D1).
///
/// Kept UI-free and dependency-light so the zone computation is unit-testable
/// without pumping widgets. [SidebarRow] consumes these to build its
/// `Draggable`/`DragTarget`, and the sidebar wires the resulting [DropZone] to
/// the pure reorder/move ops (`moveConnection`/`reorderConnection`/
/// `moveFolderOrdered`).
library;

/// The drop intent computed from the pointer's vertical position over a row.
///
/// - [before] / [after]: a sibling-reorder insertion (an accent insertion line
///   is drawn at the row's top/bottom edge, at the TARGET depth).
/// - [into]: nest the dragged node INTO this folder row (a distinct outline +
///   soft fill highlight — never the same visual as reorder or selected).
enum DropZone { before, after, into }

/// Identity of the node being dragged. A host carries [connectionId]; a folder
/// carries [folderId] with [isFolder] true. [sourceDepth] is the row's tree
/// depth at drag start (carried for callers that want it; the drop math itself
/// uses the TARGET row's depth for the insertion line).
class SidebarDragData {
  final String id;
  final bool isFolder;
  final int sourceDepth;

  const SidebarDragData({
    required this.id,
    required this.isFolder,
    this.sourceDepth = 0,
  });

  bool get isConnection => !isFolder;
}

/// Top/bottom fraction of a row that maps to the before/after reorder zones.
/// The middle band (1 - 2 * [kEdgeZoneFraction]) is the move-into zone on a
/// folder row. ~30% / ~40% / ~30% per ADR 0035 D1/B2.
const double kEdgeZoneFraction = 0.30;

/// Computes the [DropZone] for a pointer at [localY] over a row of [height].
///
/// - Top [kEdgeZoneFraction] → [DropZone.before].
/// - Bottom [kEdgeZoneFraction] → [DropZone.after].
/// - Middle band → [DropZone.into] when [isFolder] (nest), else falls back to
///   [DropZone.after] for a host row (a host can't contain children).
///
/// [localY] is clamped to `[0, height]` so an over-scrolled pointer still
/// resolves to a valid zone. Pure — no widgets, no side effects.
DropZone zoneFor(double localY, double height, {required bool isFolder}) {
  if (height <= 0) return DropZone.after;
  final y = localY.clamp(0.0, height);
  final top = height * kEdgeZoneFraction;
  final bottom = height * (1 - kEdgeZoneFraction);
  if (y < top) return DropZone.before;
  if (y > bottom) return DropZone.after;
  // Middle band.
  return isFolder ? DropZone.into : DropZone.after;
}
