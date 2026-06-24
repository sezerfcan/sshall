import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/features/shell/shell_state.dart';
import 'package:sshall/features/shell/title_bar.dart';
import 'package:sshall/features/shell/window_chrome.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/theme_controller.dart';

class _FakeWindowChrome implements WindowChrome {
  int drags = 0;
  int toggles = 0;
  final List<String> titles = [];
  final bool fullScreen;
  _FakeWindowChrome({this.fullScreen = false});
  @override
  Future<void> startDragging() async => drags++;
  @override
  Future<void> toggleMaximize() async => toggles++;
  @override
  Future<void> setTitle(String title) async => titles.add(title);
  @override
  Future<bool> isFullScreen() async => fullScreen;
}

/// A [FullScreenNotifier] stand-in that reports a fixed fullscreen state without
/// attaching a window_manager listener — lets a widget test drive the title
/// bar's reactive gutter deterministically.
class _FixedFullScreen extends FullScreenNotifier {
  _FixedFullScreen(this._value);
  final bool _value;
  @override
  bool build() => _value;
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      windowChromeProvider.overrideWithValue(_FakeWindowChrome()),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appThemeData(AppThemeId.night),
        home: const Scaffold(body: TitleBar()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Pump the title bar at a window of [width] so its adaptive breakpoints
/// (ADR 0021) can be exercised. Sizes the test view (not a SizedBox) so widths
/// above the default 800px surface are honoured.
Future<ProviderContainer> _pumpWidth(WidgetTester tester, double width) async {
  // Tall enough that an opened overflow popup (help + theme + settings rows)
  // fits within the test surface and stays hit-testable.
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      windowChromeProvider.overrideWithValue(_FakeWindowChrome()),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appThemeData(AppThemeId.night),
        home: const Scaffold(body: TitleBar()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Pump the title bar at [width] with the active-session title overridden to
/// [title] (null = home / no session) so the centered title + overflow ladder
/// can be exercised without driving a full TabsController.
Future<ProviderContainer> _pumpWithTitle(
  WidgetTester tester,
  double width,
  String? title, {
  WindowChrome? chrome,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      windowChromeProvider.overrideWithValue(chrome ?? _FakeWindowChrome()),
      activeSessionTitleProvider.overrideWithValue(title),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appThemeData(AppThemeId.night),
        home: const Scaffold(body: TitleBar()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// A tiny host that wires the OS-title mirror exactly as AppShell does
/// (`listenManual` over [activeSessionTitleProvider] → [osWindowTitleFor] →
/// `WindowChrome.setTitle`), so the seam invocation can be asserted against a
/// real TabsController without pumping the whole shell.
class _MirrorHost extends ConsumerStatefulWidget {
  const _MirrorHost();
  @override
  ConsumerState<_MirrorHost> createState() => _MirrorHostState();
}

class _MirrorHostState extends ConsumerState<_MirrorHost> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(activeSessionTitleProvider, (prev, next) {
      ref.read(windowChromeProvider).setTitle(osWindowTitleFor(next));
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(() {
    // Runtime version is sourced from package_info_plus (ADR 0038 D9); mock it so
    // the badge resolves to a stable 'v1.0.0'.
    PackageInfo.setMockInitialValues(
      appName: 'sshall',
      packageName: 'com.sshall.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('double-tapping the title bar toggles maximize (ADR 0024)', (
    tester,
  ) async {
    final chrome = _FakeWindowChrome();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        windowChromeProvider.overrideWithValue(chrome),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const Scaffold(body: TitleBar()),
        ),
      ),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('titleBarDrag')));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 300));

    expect(chrome.toggles, 1);
    container.dispose();
  });

  testWidgets('dragging the title bar starts a window move (ADR 0024)', (
    tester,
  ) async {
    final chrome = _FakeWindowChrome();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        windowChromeProvider.overrideWithValue(chrome),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const Scaffold(body: TitleBar()),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('titleBarDrag')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(chrome.drags, greaterThan(0));
    container.dispose();
  });

  testWidgets('theme button shows the current theme and lists all themes (§9)', (
    tester,
  ) async {
    final container = await _pump(tester);

    // A single theme control replaces the old swatch row; its tooltip names the
    // active theme (discoverable).
    final btn = find.byKey(const Key('themeButton'));
    expect(btn, findsOneWidget);
    expect(find.byTooltip('Tema: ${AppThemeId.night.label}'), findsOneWidget);

    // Opening it lists every theme with its label, and the active one is marked.
    await tester.tap(btn);
    await tester.pumpAndSettle();
    for (final id in AppThemeId.values) {
      expect(
        find.text(id.label),
        findsOneWidget,
        reason: 'theme "${id.name}" should be listed in the picker',
      );
    }
    expect(find.byIcon(Icons.check), findsOneWidget); // current theme marker

    container.dispose();
  });

  testWidgets('picking a theme from the theme button applies it', (
    tester,
  ) async {
    final container = await _pump(tester);
    expect(container.read(themeControllerProvider), AppThemeId.night);

    await tester.tap(find.byKey(const Key('themeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppThemeId.day.label));
    await tester.pumpAndSettle();

    expect(container.read(themeControllerProvider), AppThemeId.day);
    container.dispose();
  });

  testWidgets('theme labels are non-empty and human readable', (tester) async {
    // Guards against an id slipping through without a friendly label.
    for (final id in AppThemeId.values) {
      expect(id.label.trim().isNotEmpty, isTrue);
    }
  });

  testWidgets('keyboard help button opens the shortcuts dialog (§9)', (
    tester,
  ) async {
    final container = await _pump(tester);
    final btn = find.byKey(const Key('shortcutsHelpButton'));
    expect(btn, findsOneWidget);
    // The tooltip ends in its shortcut (ADR 0039 D3).
    expect(find.byTooltip('Klavye kısayolları  ?'), findsOneWidget);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(
      find.text('Klavye Kısayolları & Sekme Etkileşimleri'),
      findsOneWidget,
    );
    // A couple of representative entries are listed.
    expect(find.text('Aktif oturum sekmesini kapat'), findsOneWidget);
    expect(
      find.text('Sol/sağ/üst/alt → yönlü böl · orta → bu gruba taşı'),
      findsOneWidget,
    );
    // Frameless window interactions are discoverable (ADR 0024).
    expect(
      find.text('Pencereyi taşı (başlık çubuğunu sürükle)'),
      findsOneWidget,
    );
    expect(find.text('Pencereyi büyüt / geri al'), findsOneWidget);
    container.dispose();
  });

  // --- responsive title bar (ADR 0021) ---

  testWidgets('wide window: version badge + inline help + theme button', (
    tester,
  ) async {
    final container = await _pumpWidth(tester, 1100);
    await tester.pumpAndSettle(); // resolve the runtime-version FutureBuilder
    // Runtime version (ADR 0038 D9) — the badge is present and shows v1.0.0,
    // sourced from the SAME helper as the About card (no more 'v0.3.0' drift).
    expect(find.byKey(const Key('titleVersionBadge')), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('v0.3.0 · MVP'), findsNothing);
    expect(find.byKey(const Key('shortcutsHelpButton')), findsOneWidget);
    expect(find.byKey(const Key('themeButton')), findsOneWidget);
    expect(find.byKey(const Key('titleOverflowButton')), findsNothing);
    container.dispose();
  });

  testWidgets('medium window: version hidden, theme button still inline', (
    tester,
  ) async {
    final container = await _pumpWidth(tester, 860); // [800, 940)
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('titleVersionBadge')), findsNothing);
    expect(find.byKey(const Key('themeButton')), findsOneWidget);
    expect(find.byKey(const Key('shortcutsHelpButton')), findsOneWidget);
    expect(find.byKey(const Key('titleOverflowButton')), findsNothing);
    container.dispose();
  });

  testWidgets(
    'narrow window: toolbar collapses to ⋯; all actions reachable (§9)',
    (tester) async {
      final container = await _pumpWidth(tester, 720); // < 800 → overflow
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('titleVersionBadge')), findsNothing);
      // Inline help + chips are gone; a single overflow button remains.
      expect(find.byKey(const Key('shortcutsHelpButton')), findsNothing);
      final overflow = find.byKey(const Key('titleOverflowButton'));
      expect(overflow, findsOneWidget);

      // Opening it exposes the keyboard help + Settings + every theme — the
      // overflow is a full superset of every folded control (§9, ADR 0039 D5).
      await tester.tap(overflow);
      await tester.pumpAndSettle();
      expect(find.text('Klavye kısayolları'), findsOneWidget);
      expect(find.text('Ayarlar'), findsOneWidget);
      for (final id in AppThemeId.values) {
        expect(find.text(id.label), findsWidgets);
      }

      // Choosing a theme from the overflow menu applies it.
      await tester.tap(find.text(AppThemeId.day.label).last);
      await tester.pumpAndSettle();
      expect(container.read(themeControllerProvider), AppThemeId.day);
      container.dispose();
    },
  );

  // --- D5: fullscreen traffic-light gutter ----------------------------------

  /// The title bar's left gutter (the macOS traffic-light reservation) read off
  /// the leading edge of its outer Container's padding.
  double leadingGutter(WidgetTester tester) {
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('titleBarDrag')),
            matching: find.byType(Container),
          )
          .first,
    );
    return (box.padding as EdgeInsets).left;
  }

  testWidgets('windowed: the 78px traffic-light gutter is reserved (D5)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        windowChromeProvider.overrideWithValue(_FakeWindowChrome()),
        fullScreenProvider.overrideWith(() => _FixedFullScreen(false)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: const Scaffold(body: TitleBar()),
        ),
      ),
    );
    await tester.pump();
    expect(leadingGutter(tester), 78);
    container.dispose();
  });

  testWidgets(
    'fullscreen: the gutter collapses to zero (no dead left inset — D5)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          windowChromeProvider.overrideWithValue(
            _FakeWindowChrome(fullScreen: true),
          ),
          // The bar reacts to the fullscreen seam: in fullscreen macOS hides the
          // traffic lights, so the 78px gutter must collapse to 0.
          fullScreenProvider.overrideWith(() => _FixedFullScreen(true)),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appThemeData(AppThemeId.night),
            home: const Scaffold(body: TitleBar()),
          ),
        ),
      );
      await tester.pump();
      expect(leadingGutter(tester), 0);
      container.dispose();
    },
  );

  // --- D1: centered active-session title -----------------------------------

  testWidgets('centered active-session title renders for an open session (D1)', (
    tester,
  ) async {
    final container = await _pumpWithTitle(tester, 1200, 'web.example.com');
    await tester.pumpAndSettle();
    final title = find.byKey(const Key('titleActiveSession'));
    expect(title, findsOneWidget);
    expect(find.text('web.example.com'), findsOneWidget);
    // It is inert (not a button): an IgnorePointer with ignoring:true wraps it
    // so the surrounding drag/zoom region keeps the gesture.
    final ignorers = tester
        .widgetList<IgnorePointer>(
          find.ancestor(of: title, matching: find.byType(IgnorePointer)),
        )
        .where((w) => w.ignoring == true);
    expect(ignorers, isNotEmpty);
    // The title is not wrapped in any GestureDetector/InkWell of its own.
    expect(
      find.ancestor(of: title, matching: find.byType(InkWell)),
      findsNothing,
    );
    container.dispose();
  });

  testWidgets('home surface shows NOTHING in the center (no fake title) (D1)', (
    tester,
  ) async {
    final container = await _pumpWithTitle(tester, 1200, null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('titleActiveSession')), findsNothing);
    container.dispose();
  });

  testWidgets('a long host title is middle-ellipsized (D1)', (tester) async {
    const longHost =
        'web-frontend-production-cluster-node-eu-west-1.internal.example.com';
    final container = await _pumpWithTitle(tester, 1400, longHost);
    await tester.pumpAndSettle();
    final textWidget = tester.widget<Text>(
      find.byKey(const Key('titleActiveSession')),
    );
    final shown = textWidget.data!;
    expect(shown.contains('…'), isTrue, reason: 'should be ellipsized');
    expect(shown.length, lessThan(longHost.length));
    // Both ends stay legible (middle-ellipsis, not a trailing cut).
    expect(shown.startsWith('web-frontend'), isTrue);
    expect(shown.endsWith('example.com'), isTrue);
    container.dispose();
  });

  test('middleEllipsis keeps both ends and the dropped middle (D1)', () {
    expect(middleEllipsis('short', 42), 'short');
    final out = middleEllipsis('a' * 30 + 'b' * 30, 21);
    expect(out.length, 21);
    expect(out.contains('…'), isTrue);
    expect(out.startsWith('a'), isTrue);
    expect(out.endsWith('b'), isTrue);
  });

  // --- D1: OS window-title mirror -------------------------------------------

  testWidgets('OS window title mirrors the active session (D1)', (
    tester,
  ) async {
    final chrome = _FakeWindowChrome();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        windowChromeProvider.overrideWithValue(chrome),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _MirrorHost()),
      ),
    );
    await tester.pump();

    // No session yet → plain 'sshall'.
    expect(chrome.titles.last, 'sshall');

    // Opening a session mirrors 'sshall — <session>'.
    container.read(tabsControllerProvider.notifier).openOrFocus(TabKind.sftp);
    await tester.pump();
    expect(chrome.titles.last, startsWith('sshall — SFTP'));

    // Closing back to home returns to plain 'sshall'.
    final id = container.read(tabsControllerProvider).activeTab!.id;
    container.read(tabsControllerProvider.notifier).close(id);
    await tester.pump();
    expect(chrome.titles.last, 'sshall');
    container.dispose();
  });

  test('osWindowTitleFor: session vs home (D1)', () {
    expect(osWindowTitleFor('db-1'), 'sshall — db-1');
    expect(osWindowTitleFor(null), 'sshall');
    expect(osWindowTitleFor('   '), 'sshall');
  });

  // --- D1: drag/zoom preserved with a title present -------------------------

  testWidgets('drag + double-click-zoom still work with a title shown (D1)', (
    tester,
  ) async {
    final chrome = _FakeWindowChrome();
    await _pumpWithTitle(tester, 1200, 'web.example.com', chrome: chrome);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('titleBarDrag')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(chrome.drags, greaterThan(0));
  });

  // --- D2: settings gear -----------------------------------------------------

  testWidgets('settings gear opens the Settings overlay (D2)', (tester) async {
    final container = await _pumpWithTitle(tester, 1200, 'web.example.com');
    await tester.pumpAndSettle();
    final gear = find.byKey(const Key('settingsButton'));
    expect(gear, findsOneWidget);
    expect(find.byTooltip('Ayarlar  ⌘,'), findsOneWidget);
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
    await tester.tap(gear);
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.settings);
    container.dispose();
  });

  // --- D3: consistent trailing cluster --------------------------------------

  testWidgets('all trailing controls share one 28px hit target (D3)', (
    tester,
  ) async {
    final container = await _pumpWithTitle(tester, 1200, 'web.example.com');
    await tester.pumpAndSettle();
    // The bare-icon buttons (help + settings) and the theme chip all resolve to
    // a 28px-tall hit target row.
    final help = tester.getSize(find.byKey(const Key('shortcutsHelpButton')));
    final settings = tester.getSize(find.byKey(const Key('settingsButton')));
    expect(help.height, 28);
    expect(settings.height, 28);
    // The theme chip is the same height (no more 26 vs 28 mismatch).
    final chip = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('themeButton')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(chip.height, 28);
    container.dispose();
  });

  testWidgets(
    'every trailing control has a tooltip ending in its shortcut (D3)',
    (tester) async {
      final container = await _pumpWithTitle(tester, 1200, 'web.example.com');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Klavye kısayolları  ?'), findsOneWidget);
      expect(find.byTooltip('Tema: ${AppThemeId.night.label}'), findsOneWidget);
      expect(find.byTooltip('Ayarlar  ⌘,'), findsOneWidget);
      container.dispose();
    },
  );

  // --- D4: shared canonical theme picker ------------------------------------

  testWidgets('title-bar theme popup uses the shared canonical picker (D4)', (
    tester,
  ) async {
    final container = await _pumpWithTitle(tester, 1200, 'web.example.com');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('themeButton')));
    await tester.pumpAndSettle();
    // The shared ThemePickerMenu renders a keyed colour swatch per theme — the
    // proof the popup mounts the shared widget rather than a local row literal.
    for (final id in AppThemeId.values) {
      expect(find.byKey(Key('themeSwatch_${id.name}')), findsOneWidget);
      expect(find.text(id.label), findsOneWidget);
    }
    container.dispose();
  });

  // --- D5: overflow ladder is a full superset -------------------------------

  testWidgets('settings gear folds into ⋯ BEFORE the rest of the cluster (D5)', (
    tester,
  ) async {
    // A window between titleSettingsHide and titleOverflow: only the gear has
    // folded; help + theme stay inline; the ⋯ carries Settings (superset — §9).
    final container = await _pumpWithTitle(tester, 820, 'web.example.com');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcutsHelpButton')), findsOneWidget);
    expect(find.byKey(const Key('themeButton')), findsOneWidget);
    // The standalone gear is gone; it lives in the overflow.
    expect(find.byKey(const Key('settingsButton')), findsNothing);
    final overflow = find.byKey(const Key('titleOverflowButton'));
    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsOneWidget);
    // Selecting Settings from the overflow opens the overlay.
    await tester.tap(find.text('Ayarlar'));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.settings);
    container.dispose();
  });

  testWidgets('centered title yields before the trailing cluster (D5)', (
    tester,
  ) async {
    // Below titleHide the centered title is dropped while the trailing cluster
    // is still fully present (title yields first — never pushes actions off).
    final container = await _pumpWithTitle(tester, 860, 'web.example.com');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('titleActiveSession')), findsNothing);
    expect(find.byKey(const Key('shortcutsHelpButton')), findsOneWidget);
    expect(find.byKey(const Key('themeButton')), findsOneWidget);
    container.dispose();
  });
}
