import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/sidebar_drag.dart';

void main() {
  const h = 100.0; // edge zones at <30 and >70.

  group('zoneFor — host row (no nesting)', () {
    test('top third → before', () {
      expect(zoneFor(5, h, isFolder: false), DropZone.before);
      expect(zoneFor(29, h, isFolder: false), DropZone.before);
    });
    test(
      'middle band falls back to after (a host cannot contain children)',
      () {
        expect(zoneFor(50, h, isFolder: false), DropZone.after);
      },
    );
    test('bottom third → after', () {
      expect(zoneFor(71, h, isFolder: false), DropZone.after);
      expect(zoneFor(99, h, isFolder: false), DropZone.after);
    });
  });

  group('zoneFor — folder row (nesting allowed)', () {
    test('top third → before', () {
      expect(zoneFor(10, h, isFolder: true), DropZone.before);
    });
    test('middle band → into', () {
      expect(zoneFor(40, h, isFolder: true), DropZone.into);
      expect(zoneFor(60, h, isFolder: true), DropZone.into);
    });
    test('bottom third → after', () {
      expect(zoneFor(80, h, isFolder: true), DropZone.after);
    });
  });

  group('zoneFor — boundaries & clamping', () {
    test('exactly at the 30% boundary is NOT before (band starts mid)', () {
      // y == top (30) is not strictly < top, so it is the middle band.
      expect(zoneFor(30, h, isFolder: true), DropZone.into);
    });
    test('over/under-scroll is clamped to a valid zone', () {
      expect(zoneFor(-50, h, isFolder: true), DropZone.before);
      expect(zoneFor(500, h, isFolder: true), DropZone.after);
    });
    test('degenerate height resolves to after', () {
      expect(zoneFor(0, 0, isFolder: true), DropZone.after);
    });
  });

  test('SidebarDragData distinguishes host vs folder', () {
    const host = SidebarDragData(id: 'c1', isFolder: false);
    const folder = SidebarDragData(id: 'f1', isFolder: true, sourceDepth: 2);
    expect(host.isConnection, isTrue);
    expect(folder.isFolder, isTrue);
    expect(folder.sourceDepth, 2);
  });
}
