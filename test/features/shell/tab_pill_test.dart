import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/tab_pill.dart';
import 'package:sshall/features/terminal/session_status.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(extensions: const [AppColors.night]),
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );

  TabPill pill(
    ShellTab tab, {
    bool active = false,
    bool iconOnly = false,
    ValueListenable<SessionStatus>? status,
    void Function()? onSelect,
    void Function()? onClose,
    void Function(Offset)? onContextMenu,
    void Function(String)? onRename,
  }) => TabPill(
    tab: tab,
    active: active,
    isActiveGroup: true,
    sourceGroupId: 'g0',
    sessionStatus: status,
    iconOnly: iconOnly,
    onSelect: onSelect ?? () {},
    onClose: onClose ?? () {},
    onContextMenu: onContextMenu ?? (_) {},
    onRename: onRename,
    onDragStarted: () {},
    onDragEnd: () {},
  );

  testWidgets('terminal tab shows a status dot when not hovered, ✕ on hover', (
    tester,
  ) async {
    final status = ValueNotifier<SessionStatus>(
      const SessionStatus.connected(),
    );
    await tester.pumpWidget(
      host(
        pill(
          const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1:22'),
          status: status,
        ),
      ),
    );

    // Not hovered: status dot present, close button absent.
    expect(find.byKey(const Key('statusDot_t0')), findsOneWidget);
    expect(find.byKey(const Key('closeTab_t0')), findsNothing);

    // Hover → close button appears.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('tab_t0'))));
    await tester.pump();
    expect(find.byKey(const Key('closeTab_t0')), findsOneWidget);
  });

  testWidgets('an SFTP session tab is closable (✕ on the active tab)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        pill(
          const ShellTab(id: 's0', kind: TabKind.sftp, title: 'SFTP'),
          active: true,
        ),
      ),
    );
    // Every session tab is closable now (ADR 0022): the active tab shows ✕.
    expect(find.byKey(const Key('closeTab_s0')), findsOneWidget);
    expect(find.text('SFTP'), findsOneWidget);
  });

  testWidgets(
    'pinned tab keeps identity: short title + pin glyph, no visible ✕ '
    '(ADR 0036 D4)',
    (tester) async {
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(
              id: 't0',
              kind: TabKind.terminal,
              title: 'web1:22',
              pinned: true,
            ),
          ),
        ),
      );
      // Pinned is no longer anonymous: its (truncated) title is shown.
      expect(find.text('web1:22'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      // Closing a pinned tab stays via middle-click / menu — no hover ✕.
      expect(find.byKey(const Key('closeTab_t0')), findsNothing);
    },
  );

  testWidgets('pinned tab shows the live status dot (ADR 0036 D4 / 0032)', (
    tester,
  ) async {
    final status = ValueNotifier<SessionStatus>(
      const SessionStatus.connected(),
    );
    await tester.pumpWidget(
      host(
        pill(
          const ShellTab(
            id: 't0',
            kind: TabKind.terminal,
            title: 'web1:22',
            pinned: true,
          ),
          status: status,
        ),
      ),
    );
    expect(find.byKey(const Key('statusDot_t0')), findsOneWidget);
    // Even hovered, a pinned tab never shows a close ✕ (close = middle/menu).
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('tab_t0'))));
    await tester.pump();
    expect(find.byKey(const Key('closeTab_t0')), findsNothing);
  });

  testWidgets('pinned tab never collapses to icon-only (ADR 0036 D4)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        pill(
          const ShellTab(
            id: 't0',
            kind: TabKind.terminal,
            title: 'prod',
            pinned: true,
          ),
          iconOnly: true, // narrow panel; pinned must ignore this
        ),
      ),
    );
    // The short title stays visible even at icon-only density.
    expect(find.text('prod'), findsOneWidget);
  });

  testWidgets(
    'icon-only pill hides the title (tooltip keeps it) + ✕ on hover',
    (tester) async {
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1:22'),
            iconOnly: true,
          ),
        ),
      );
      // Title is not rendered inline at this density...
      expect(find.text('web1:22'), findsNothing);
      // ...but the pill still exposes it via its tooltip.
      expect(find.byTooltip('web1:22'), findsOneWidget);

      // Hover still reveals the close button.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('tab_t0'))));
      await tester.pump();
      expect(find.byKey(const Key('closeTab_t0')), findsOneWidget);
    },
  );

  group('inline rename (ADR 0036 D2)', () {
    testWidgets('double-click title opens an editor prefilled + selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1'),
            onRename: (_) {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump();
      expect(find.byKey(const Key('renameField_t0')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('renameField_t0')),
      );
      expect(field.controller!.text, 'web1');
      expect(field.controller!.selection.start, 0);
      expect(field.controller!.selection.end, 'web1'.length);
    });

    testWidgets('Enter commits the new title via onRename', (tester) async {
      String? renamed;
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1'),
            onRename: (v) => renamed = v,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('renameField_t0')), 'yeni');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(renamed, 'yeni');
      expect(find.byKey(const Key('renameField_t0')), findsNothing);
    });

    testWidgets('Esc cancels — onRename NOT called, editor closes', (
      tester,
    ) async {
      var renameCalls = 0;
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1'),
            onRename: (_) => renameCalls++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('renameField_t0')),
        'changed',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(renameCalls, 0); // cancel does not commit
      expect(find.byKey(const Key('renameField_t0')), findsNothing);
      expect(find.text('web1'), findsOneWidget); // old title preserved
    });

    testWidgets('pill shows effectiveTitle (customTitle over derived)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(
              id: 't0',
              kind: TabKind.terminal,
              title: 'web1:22',
              customTitle: 'prod-db',
            ),
            onRename: (_) {},
          ),
        ),
      );
      expect(find.text('prod-db'), findsOneWidget);
      expect(find.text('web1:22'), findsNothing);
      expect(find.byTooltip('prod-db'), findsOneWidget);
    });

    testWidgets('single-tap on the title still selects (no editor)', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        host(
          pill(
            const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1'),
            onSelect: () => selected = 't0',
            onRename: (_) {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('renameTitle_t0')));
      await tester.pump();
      expect(selected, 't0');
      expect(find.byKey(const Key('renameField_t0')), findsNothing);
    });
  });

  testWidgets('tap selects; middle-click closes; right-click opens menu hook', (
    tester,
  ) async {
    String? selected;
    String closed = '';
    Offset? menuAt;
    await tester.pumpWidget(
      host(
        pill(
          const ShellTab(id: 't0', kind: TabKind.terminal, title: 'web1'),
          onSelect: () => selected = 't0',
          onClose: () => closed = 't0',
          onContextMenu: (p) => menuAt = p,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('tab_t0')));
    expect(selected, 't0');

    // Middle-click → onClose.
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('tab_t0'))),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await g.up();
    await tester.pump();
    expect(closed, 't0');

    // Right-click → onContextMenu with a position.
    await tester.tap(
      find.byKey(const Key('tab_t0')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(menuAt, isNotNull);
  });
}
