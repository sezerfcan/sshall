import 'package:flutter/foundation.dart';

/// The layout side of the shell (ADR 0019). A [SplitNode] tree arranges editor
/// groups into nested horizontal/vertical splits with per-branch weights. The
/// tree is layout-only: tab membership lives in `TabsState.groups`/`tabs`, and
/// the invariant `tree.groupIds == groups.ids` is maintained by the controller.
///
/// This file is pure Dart (no widgets) so the tree algebra can be unit-tested in
/// isolation.

/// Main axis along which a branch lays out its children.
/// [horizontal] = side by side (a Row); [vertical] = stacked (a Column).
enum SplitAxis { horizontal, vertical }

/// Where a tab was dropped on a group body (full-area directional drop).
enum DropZone { left, right, top, bottom, center }

SplitAxis _axisFor(DropZone z) => (z == DropZone.left || z == DropZone.right)
    ? SplitAxis.horizontal
    : SplitAxis.vertical;

bool _before(DropZone z) => z == DropZone.left || z == DropZone.top;

sealed class SplitNode {
  const SplitNode();

  /// Every group id reachable from this node.
  Set<String> get groupIds;
}

/// A single editor group occupies a leaf.
class GroupLeaf extends SplitNode {
  final String groupId;
  const GroupLeaf(this.groupId);

  @override
  Set<String> get groupIds => {groupId};

  @override
  bool operator ==(Object other) =>
      other is GroupLeaf && other.groupId == groupId;

  @override
  int get hashCode => groupId.hashCode;

  @override
  String toString() => 'Leaf($groupId)';
}

/// A branch lays out [children] along [axis] with normalized [weights]
/// (same length as children, summing to 1).
class SplitBranch extends SplitNode {
  final SplitAxis axis;
  final List<SplitNode> children;
  final List<double> weights;

  SplitBranch(this.axis, this.children, this.weights)
    : assert(children.length == weights.length),
      assert(children.isNotEmpty);

  @override
  Set<String> get groupIds => {for (final c in children) ...c.groupIds};

  @override
  bool operator ==(Object other) =>
      other is SplitBranch &&
      other.axis == axis &&
      listEquals(other.children, children) &&
      listEquals(other.weights, weights);

  @override
  int get hashCode => Object.hash(axis, Object.hashAll(children));

  @override
  String toString() => '${axis.name}($children @ $weights)';
}

List<double> _normalize(List<double> weights) {
  final sum = weights.fold<double>(0, (s, w) => s + w);
  if (sum <= 0) return equalWeights(weights.length);
  return [for (final w in weights) w / sum];
}

/// Equal weights for [n] children (sums to 1).
List<double> equalWeights(int n) =>
    n <= 0 ? const [] : List<double>.filled(n, 1 / n);

/// DFS leaf order — the canonical left→right / top→bottom reading order used for
/// the group index (⌘1..9) and to keep `groups` ordered.
List<String> orderedLeafIds(SplitNode node) => switch (node) {
  GroupLeaf(:final groupId) => [groupId],
  SplitBranch(:final children) => [
    for (final c in children) ...orderedLeafIds(c),
  ],
};

/// Insert [newId] as a new leaf adjacent to [targetId] in the direction implied
/// by [zone] (left/right → horizontal, top/bottom → vertical). [DropZone.center]
/// is not a split and must be handled by the caller as a move.
SplitNode insertLeaf(
  SplitNode root,
  String targetId,
  String newId,
  DropZone zone,
) {
  if (zone == DropZone.center) return root;
  final axis = _axisFor(zone);
  final before = _before(zone);
  final newLeaf = GroupLeaf(newId);

  SplitNode wrapTarget(SplitNode target) => SplitBranch(
    axis,
    before ? [newLeaf, target] : [target, newLeaf],
    const [0.5, 0.5],
  );

  SplitNode go(SplitNode node) {
    if (node is GroupLeaf) {
      // Only reachable for the root leaf; a branch handles its own leaf children.
      return node.groupId == targetId ? wrapTarget(node) : node;
    }
    final branch = node as SplitBranch;
    final idx = branch.children.indexWhere(
      (c) => c is GroupLeaf && c.groupId == targetId,
    );
    if (idx >= 0) {
      if (branch.axis == axis) {
        // Same axis: insert a sibling next to the target, splitting its weight.
        final w = branch.weights[idx];
        final children = List<SplitNode>.from(branch.children);
        final weights = List<double>.from(branch.weights);
        final insertAt = before ? idx : idx + 1;
        children.insert(insertAt, newLeaf);
        weights[idx] = w / 2;
        weights.insert(insertAt, w / 2);
        return SplitBranch(branch.axis, children, _normalize(weights));
      }
      // Perpendicular axis: wrap the target leaf in a sub-branch in its slot.
      final children = List<SplitNode>.from(branch.children)
        ..[idx] = wrapTarget(branch.children[idx]);
      return SplitBranch(branch.axis, children, branch.weights);
    }
    // Target is deeper: recurse.
    return SplitBranch(
      branch.axis,
      branch.children.map(go).toList(),
      branch.weights,
    );
  }

  return go(root);
}

/// Remove the leaf for [id]. Single-child branches collapse (the child takes the
/// branch's slot/weight). Removing the only remaining leaf is a no-op.
SplitNode removeLeaf(SplitNode root, String id) {
  SplitNode? go(SplitNode node) {
    if (node is GroupLeaf) return node.groupId == id ? null : node;
    final branch = node as SplitBranch;
    final children = <SplitNode>[];
    final weights = <double>[];
    for (var i = 0; i < branch.children.length; i++) {
      final r = go(branch.children[i]);
      if (r != null) {
        children.add(r);
        weights.add(branch.weights[i]);
      }
    }
    if (children.isEmpty) return null;
    if (children.length == 1) return children.first; // collapse
    return SplitBranch(branch.axis, children, _normalize(weights));
  }

  return go(root) ?? root;
}

/// Replace the weights of the branch addressed by [path] (a list of child
/// indices from the root; `[]` = the root branch). Weights are normalized.
SplitNode updateWeightsAt(
  SplitNode root,
  List<int> path,
  List<double> weights,
) {
  SplitNode go(SplitNode node, int depth) {
    if (depth == path.length) {
      if (node is! SplitBranch) return node;
      return SplitBranch(node.axis, node.children, _normalize(weights));
    }
    if (node is! SplitBranch) return node;
    final i = path[depth];
    if (i < 0 || i >= node.children.length) return node;
    final children = List<SplitNode>.from(node.children);
    children[i] = go(children[i], depth + 1);
    return SplitBranch(node.axis, children, node.weights);
  }

  return go(root, 0);
}
