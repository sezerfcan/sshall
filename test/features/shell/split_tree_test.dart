import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/split_tree.dart';

void main() {
  group('insertLeaf', () {
    test('splitting a root leaf to the right makes a horizontal branch', () {
      final root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      expect(root, isA<SplitBranch>());
      final b = root as SplitBranch;
      expect(b.axis, SplitAxis.horizontal);
      expect(orderedLeafIds(root), ['a', 'b']);
      expect(b.weights[0], closeTo(0.5, 1e-9));
      expect(b.weights[1], closeTo(0.5, 1e-9));
    });

    test('splitting left puts the new leaf before the target', () {
      final root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.left);
      expect(orderedLeafIds(root), ['b', 'a']);
      expect((root as SplitBranch).axis, SplitAxis.horizontal);
    });

    test('splitting a root leaf to the bottom makes a vertical branch', () {
      final root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.bottom);
      expect((root as SplitBranch).axis, SplitAxis.vertical);
      expect(orderedLeafIds(root), ['a', 'b']);
    });

    test('same-axis parent inserts a sibling and splits the target weight', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      // root = H[a:.5, b:.5]; split b to the right -> H[a:.5, b:.25, c:.25]
      root = insertLeaf(root, 'b', 'c', DropZone.right);
      final br = root as SplitBranch;
      expect(br.axis, SplitAxis.horizontal);
      expect(orderedLeafIds(root), ['a', 'b', 'c']);
      expect(br.weights[0], closeTo(0.5, 1e-9));
      expect(br.weights[1], closeTo(0.25, 1e-9));
      expect(br.weights[2], closeTo(0.25, 1e-9));
    });

    test('perpendicular split wraps the target in a sub-branch', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      // root = H[a, b]; split b to the bottom -> H[a, V[b, c]]
      root = insertLeaf(root, 'b', 'c', DropZone.bottom);
      final br = root as SplitBranch;
      expect(br.axis, SplitAxis.horizontal);
      expect(br.children[0], const GroupLeaf('a'));
      expect(br.children[1], isA<SplitBranch>());
      final sub = br.children[1] as SplitBranch;
      expect(sub.axis, SplitAxis.vertical);
      expect(orderedLeafIds(root), ['a', 'b', 'c']);
    });
  });

  group('removeLeaf', () {
    test('removing one child of a 2-child branch collapses to a leaf', () {
      final root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      final after = removeLeaf(root, 'a');
      expect(after, const GroupLeaf('b'));
    });

    test('removing collapses a nested single-child branch', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      root = insertLeaf(root, 'b', 'c', DropZone.bottom); // H[a, V[b,c]]
      final after = removeLeaf(root, 'c'); // V[b,c] -> b ; H[a, b]
      expect(after, isA<SplitBranch>());
      expect((after as SplitBranch).axis, SplitAxis.horizontal);
      expect(orderedLeafIds(after), ['a', 'b']);
    });

    test('removing the last leaf is a no-op', () {
      const root = GroupLeaf('a');
      expect(removeLeaf(root, 'a'), const GroupLeaf('a'));
    });

    test('removed weights are renormalized to sum 1', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      root = insertLeaf(root, 'b', 'c', DropZone.right); // H[.5,.25,.25]
      final after = removeLeaf(root, 'a') as SplitBranch; // H[b,c]
      final sum = after.weights.fold<double>(0, (s, w) => s + w);
      expect(sum, closeTo(1.0, 1e-9));
      expect(after.weights[0], closeTo(0.5, 1e-9));
    });
  });

  group('updateWeightsAt', () {
    test('replaces the root branch weights (normalized)', () {
      final root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      final after = updateWeightsAt(root, const [], [3, 1]) as SplitBranch;
      expect(after.weights[0], closeTo(0.75, 1e-9));
      expect(after.weights[1], closeTo(0.25, 1e-9));
      expect(orderedLeafIds(after), ['a', 'b']);
    });

    test('updates a nested branch addressed by path', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      root = insertLeaf(
        root,
        'b',
        'c',
        DropZone.bottom,
      ); // H[a, V[b,c]] -> sub at index 1
      final after = updateWeightsAt(root, const [1], [1, 3]) as SplitBranch;
      final sub = after.children[1] as SplitBranch;
      expect(sub.weights[0], closeTo(0.25, 1e-9));
      expect(sub.weights[1], closeTo(0.75, 1e-9));
    });
  });

  group('helpers', () {
    test('orderedLeafIds returns DFS leaf order', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      root = insertLeaf(root, 'a', 'c', DropZone.bottom); // H[V[a,c], b]
      expect(orderedLeafIds(root), ['a', 'c', 'b']);
    });

    test('groupIds collects every leaf id', () {
      var root = insertLeaf(const GroupLeaf('a'), 'a', 'b', DropZone.right);
      root = insertLeaf(root, 'b', 'c', DropZone.bottom);
      expect(root.groupIds, {'a', 'b', 'c'});
    });

    test('equalWeights sums to 1', () {
      final w = equalWeights(4);
      expect(w.length, 4);
      expect(w.fold<double>(0, (s, x) => s + x), closeTo(1.0, 1e-9));
    });
  });
}
