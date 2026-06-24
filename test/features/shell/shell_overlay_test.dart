import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_overlay.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.night]),
          home: const Scaffold(
            body: OverlayPanel(
              icon: Icons.settings_outlined,
              title: 'Ayarlar',
              child: Text('overlay-body'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('renders header (title + close) and the child body', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Ayarlar'), findsOneWidget);
    expect(find.text('overlay-body'), findsOneWidget);
    expect(find.byKey(const Key('overlayClose')), findsOneWidget);
    expect(find.byTooltip('Kapat (Esc)'), findsOneWidget);
  });

  testWidgets('the close button sets activeOverlayProvider to none', (
    tester,
  ) async {
    final container = await pump(tester);
    // Seed a non-none overlay so we can observe the close transition.
    container.read(activeOverlayProvider.notifier).state =
        ShellOverlay.settings;
    await tester.tap(find.byKey(const Key('overlayClose')));
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
  });

  testWidgets('Esc closes the overlay (sets none)', (tester) async {
    final container = await pump(tester);
    container.read(activeOverlayProvider.notifier).state = ShellOverlay.vault;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(container.read(activeOverlayProvider), ShellOverlay.none);
  });
}
