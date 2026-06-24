import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/providers.dart';
import 'package:sshall/data/models/connection.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/data/models/vault_data.dart';
import 'package:sshall/data/secure_store/secure_store.dart';
import 'package:sshall/features/shell/connection_sidebar.dart';
import 'package:sshall/features/shell/shell_state.dart';
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

Folder _folder(String id, String name) => Folder(
  id: id,
  parentId: null,
  name: name,
  username: null,
  port: null,
  authRef: null,
  order: 0,
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
    () => Directory.systemTemp.createTemp('sshall_inter'),
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
              onSelect:
                  onSelect ??
                  (c) =>
                      container
                              .read(selectedConnectionProvider.notifier)
                              .state =
                          c,
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

VaultData _twoHosts(VaultData d) => VaultData(
  connections: [
    _conn('a', 'alpha', order: 0),
    _conn('b', 'beta-web', order: 1),
  ],
  folders: const [],
  identities: d.identities,
  pins: d.pins,
);

void main() {
  testWidgets('single-click selects only; double-click connects (pure add)', (
    tester,
  ) async {
    Connection? selected;
    Connection? connected;
    final (container, store, tmp) = await _pump(
      tester,
      _twoHosts,
      onSelect: (c) => selected = c,
      onConnect: (c) => connected = c,
    );

    // Single click → select, NOT connect.
    await tester.tap(find.byKey(const Key('host-a')));
    await tester.pump();
    expect(selected?.id, 'a');
    expect(connected, isNull);

    // Double click → connect. Two taps separated by less than kDoubleTapTimeout
    // (300ms) and more than kDoubleTapMinTime (40ms) so onDoubleTap fires.
    await tester.tap(find.byKey(const Key('host-a')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('host-a')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(connected?.id, 'a');

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('right-click selects the row and opens a context menu', (
    tester,
  ) async {
    Connection? selected;
    final (container, store, tmp) = await _pump(
      tester,
      _twoHosts,
      onSelect: (c) => selected = c,
      onConnect: (_) {},
    );

    // Secondary tap on host 'a'.
    final center = tester.getCenter(find.byKey(const Key('host-a')));
    final g = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await tester.pumpAndSettle();

    // The row is selected first, then the menu mirrors the kebab.
    expect(selected?.id, 'a');
    expect(find.text('Bağlan'), findsOneWidget);
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Klasöre taşı…'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('right-click on a folder opens the folder context menu', (
    tester,
  ) async {
    final (container, store, tmp) = await _pump(
      tester,
      (d) => VaultData(
        connections: const [],
        folders: [_folder('work', 'work')],
        identities: d.identities,
        pins: d.pins,
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('folder-work')));
    final g = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text('Yeni alt klasör'), findsOneWidget);
    expect(find.text('Varsayılanlar'), findsOneWidget);
    expect(find.text('Yeniden adlandır'), findsOneWidget);
    expect(find.text('Taşı'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets(
    'clear (x) appears only when searching, clears + restores expand',
    (tester) async {
      final (container, store, tmp) = await _pump(
        tester,
        (d) => VaultData(
          connections: [_conn('w', 'web-1', folderId: 'work')],
          folders: [_folder('work', 'work')],
          identities: d.identities,
          pins: d.pins,
        ),
      );

      // The user keeps 'work' collapsed initially.
      expect(container.read(expandedFoldersProvider), isEmpty);
      // No query yet → no clear button.
      expect(find.byKey(const Key('sidebarSearchClear')), findsNothing);

      // Search forces 'work' open to reveal the match.
      await tester.enterText(find.byKey(const Key('sidebarSearch')), 'web');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sidebarSearchClear')), findsOneWidget);
      expect(find.text('web-1'), findsOneWidget);

      // Clear → query resets AND the user's pre-search (collapsed) set returns.
      await tester.tap(find.byKey(const Key('sidebarSearchClear')));
      await tester.pumpAndSettle();
      expect(container.read(sidebarSearchProvider), '');
      expect(container.read(expandedFoldersProvider), isEmpty);
      expect(find.byKey(const Key('sidebarSearchClear')), findsNothing);

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );

  testWidgets('matched substring is highlighted in the row label', (
    tester,
  ) async {
    final (container, store, tmp) = await _pump(tester, _twoHosts);

    await tester.enterText(find.byKey(const Key('sidebarSearch')), 'web');
    await tester.pumpAndSettle();

    // The matching row renders RichText (highlight spans), not a plain Text.
    final rich = tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const Key('host-b')),
        matching: find.byType(RichText),
      ),
    );
    final spans = <String>[];
    final styles = <bool>[]; // bold?
    for (final r in rich) {
      r.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          spans.add(span.text!);
          styles.add(span.style?.fontWeight == FontWeight.w700);
        }
        return true;
      });
    }
    // 'beta-web' splits into 'beta-' (base) + 'web' (bold hit).
    expect(spans.contains('web'), isTrue);
    final hitIdx = spans.indexOf('web');
    expect(styles[hitIdx], isTrue);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets(
    'first-run empty state renders a CTA (distinct from no-results)',
    (tester) async {
      final (container, store, tmp) = await _pump(
        tester,
        (d) => VaultData(
          connections: const [],
          folders: const [],
          identities: d.identities,
          pins: d.pins,
        ),
      );

      expect(find.byKey(const Key('sidebar-empty-firstrun')), findsOneWidget);
      expect(
        find.byKey(const Key('sidebar-empty-firstrun-cta')),
        findsOneWidget,
      );
      // Not the no-results state.
      expect(find.byKey(const Key('sidebar-empty-noresults')), findsNothing);

      container.dispose();
      await tester.runAsync(() => tmp.delete(recursive: true));
    },
  );

  testWidgets('empty expanded folder shows the indented inline hint', (
    tester,
  ) async {
    final (container, store, tmp) = await _pump(
      tester,
      (d) => VaultData(
        // One host so the tree (not first-run) renders, plus an empty folder.
        connections: [_conn('h', 'host-1', order: 0)],
        folders: [_folder('empty', 'empty')],
        identities: d.identities,
        pins: d.pins,
      ),
    );

    // Expand the empty folder.
    await tester.tap(find.byKey(const Key('folder-empty')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar-empty-folder-hint')), findsOneWidget);
    expect(find.text('Boş klasör — buraya host sürükleyin'), findsOneWidget);

    container.dispose();
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
