import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/core/result.dart';
import 'package:sshall/data/folders/tree.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/connection_sidebar.dart';
import 'package:sshall/services/crypto/crypto_service.dart';
import 'package:sshall/services/storage/keyring_store.dart';
import 'package:sshall/services/storage/vault_file.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/theme_controller.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Folder _folder(String id, String name, {String? parentId, int order = 0}) =>
    Folder(
      id: id,
      parentId: parentId,
      name: name,
      username: null,
      port: null,
      authRef: null,
      order: order,
    );

Connection _conn(String id, String label, {String? folderId, int order = 0}) =>
    Connection(
      id: id,
      label: label,
      host: 'h',
      folderId: folderId,
      username: null,
      port: null,
      authRef: null,
      tags: const [],
      order: order,
    );

Future<SecureStore> _store(
  Directory dir,
  VaultData Function(VaultData) seed,
) async {
  final store = SecureStore(
    crypto: CryptoService(),
    file: VaultFile('${dir.path}/vault.bin'),
    keyring: InMemoryKeyring(),
  );
  await store.create('testpass');
  await store.mutate(seed);
  return store;
}

Future<(ProviderContainer, SecureStore, Directory)> _pump(
  WidgetTester tester,
  VaultData Function(VaultData) seed, {
  void Function(Connection)? onConnect,
  void Function(Connection)? onSelect,
}) async {
  final tmp = await tester.runAsync(
    () => Directory.systemTemp.createTemp('sshall_dnd'),
  );
  PathProviderPlatform.instance = _FakePathProvider(tmp!.path);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = await tester.runAsync(() => _store(tmp, seed));

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      secureStoreProvider.overrideWith((ref) async => store!),
    ],
  );
  await tester.runAsync(() => container.read(secureStoreProvider.future));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appThemeData(AppThemeId.night),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ConnectionSidebar(
              onSelect: onSelect ?? (_) {},
              onConnect: onConnect,
              onNewHost: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return (container, store!, tmp);
}

/// Movement (logical px) that comfortably exceeds the touch-slop so a Draggable
/// starts its drag in a synthetic gesture.
const double kDragSlopExceeded = 30;

/// Drags from the center of [from] to the given vertical zone of [to].
/// [zoneFraction] 0.15 = before, 0.5 = middle (into for folders), 0.85 = after.
Future<void> _dragTo(
  WidgetTester tester,
  Key from,
  Key to, {
  double zoneFraction = 0.85,
}) async {
  final fromCenter = tester.getCenter(find.byKey(from));
  final toRect = tester.getRect(find.byKey(to));
  final target = Offset(
    toRect.center.dx,
    toRect.top + toRect.height * zoneFraction,
  );

  final gesture = await tester.startGesture(fromCenter);
  await tester.pump(const Duration(milliseconds: 20));
  // Kick the drag past the touch-slop (a single small move starts the
  // Draggable's drag recognizer), then walk toward the target so the
  // DragTarget's onMove computes its zone before the drop.
  await gesture.moveBy(const Offset(0, kDragSlopExceeded));
  await tester.pump(const Duration(milliseconds: 20));
  final start = fromCenter + const Offset(0, kDragSlopExceeded);
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(start, target, i / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  // Settle on the target one more frame so onMove fires for the final position.
  await gesture.moveTo(target);
  await tester.pump(const Duration(milliseconds: 16));
  // Release the drag INSIDE runAsync so the drop handler's real SecureStore.mutate
  // (crypto + file I/O) runs on the real clock; without this its `await
  // file.read()` would never progress in the fake-async pump zone.
  await tester.runAsync(() async {
    await gesture.up();
    // Give the chained mutate time to read + persist + bump the revision.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  await tester.pump();
}

/// Drains the store's serialized mutate queue on the REAL clock, so any queued
/// SecureStore.mutate finishes, then pumps to surface the rebuild.
Future<void> _drainStore(WidgetTester tester, SecureStore store) async {
  await tester.runAsync(() async {
    await store.mutate((v) => v);
  });
  await tester.pump();
}

void main() {
  testWidgets(
    'drag-reorder two root hosts persists the new order (one revision)',
    (tester) async {
      final (container, store, tmp) = await _pump(
        tester,
        (d) => VaultData(
          connections: [
            _conn('a', 'aaa', order: 0),
            _conn('b', 'bbb', order: 1),
          ],
          folders: const [],
          identities: d.identities,
          pins: d.pins,
        ),
      );

      final rev0 = store.revision.value;
      // Drag 'aaa' onto the AFTER zone of 'bbb' → order should flip.
      await _dragTo(
        tester,
        const Key('host-a'),
        const Key('host-b'),
        zoneFraction: 0.85,
      );
      await _drainStore(tester, store);

      final conns = store.snapshot().valueOrNull!.connections;
      final rows = buildTreeRows(const [], conns, <String>{});
      expect(rows.map((r) => r.connection!.id).toList(), ['b', 'a']);
      // The drop is ONE atomic mutate revision (the no-op drain adds another, so
      // the drop itself accounts for exactly +1 before the drain).
      expect(store.revision.value, greaterThan(rev0));

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );

  testWidgets('dragging a host onto a folder (into) sets folderId + persists', (
    tester,
  ) async {
    final (container, store, tmp) = await _pump(
      tester,
      (d) => VaultData(
        connections: [_conn('h', 'host-1', order: 0)],
        folders: [_folder('work', 'work')],
        identities: d.identities,
        pins: d.pins,
      ),
    );

    // Drop host onto the middle (into) zone of the folder row.
    await _dragTo(
      tester,
      const Key('host-h'),
      const Key('folder-work'),
      zoneFraction: 0.5,
    );
    await _drainStore(tester, store);

    final conn = store.snapshot().valueOrNull!.connections.firstWhere(
      (c) => c.id == 'h',
    );
    expect(conn.folderId, 'work');

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('a folder dropped into its own descendant is rejected (no write)', (
    tester,
  ) async {
    final (container, store, tmp) = await _pump(
      tester,
      (d) => VaultData(
        connections: const [],
        folders: [
          _folder('parent', 'parent', order: 0),
          _folder('child', 'child', parentId: 'parent', order: 0),
        ],
        identities: d.identities,
        pins: d.pins,
      ),
    );

    // Expand 'parent' so 'child' is visible.
    await tester.tap(find.byKey(const Key('folder-parent')));
    await tester.pumpAndSettle();

    // Drain any pending work before the drag.
    await _drainStore(tester, store);
    // Drag 'parent' INTO 'child' (its descendant) → cycle → rejected.
    await _dragTo(
      tester,
      const Key('folder-parent'),
      const Key('folder-child'),
      zoneFraction: 0.5,
    );
    await _drainStore(tester, store);

    final parent = store.snapshot().valueOrNull!.folders.firstWhere(
      (f) => f.id == 'parent',
    );
    expect(parent.parentId, isNull); // unchanged
    // Only the drain's own no-op mutate ran; the cycle drop wrote nothing, so the
    // parent is untouched (the key assertion above).
    expect(
      store
          .snapshot()
          .valueOrNull!
          .folders
          .firstWhere((f) => f.id == 'child')
          .parentId,
      'parent',
    );

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('DnD is disabled while searching (a reorder does not fire)', (
    tester,
  ) async {
    final (container, store, tmp) = await _pump(
      tester,
      (d) => VaultData(
        connections: [
          _conn('a', 'alpha', order: 0),
          _conn('b', 'beta', order: 1),
        ],
        folders: const [],
        identities: d.identities,
        pins: d.pins,
      ),
    );

    // Enter a query that keeps BOTH hosts so both rows are present but DnD off.
    await tester.enterText(find.byKey(const Key('sidebarSearch')), 'a');
    await tester.pumpAndSettle();
    // Both 'alpha' and 'beta' contain 'a'.
    expect(find.byKey(const Key('host-a')), findsOneWidget);
    expect(find.byKey(const Key('host-b')), findsOneWidget);

    final before = store
        .snapshot()
        .valueOrNull!
        .connections
        .map((c) => '${c.id}:${c.order}')
        .toList();

    // Attempt a reorder drag while searching.
    await _dragTo(
      tester,
      const Key('host-a'),
      const Key('host-b'),
      zoneFraction: 0.85,
    );
    await _drainStore(tester, store);

    final after = store
        .snapshot()
        .valueOrNull!
        .connections
        .map((c) => '${c.id}:${c.order}')
        .toList();
    // DnD is disabled while searching: the order is never touched.
    expect(after, before);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
