import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/context_ext.dart';
import 'package:sshall/theme/tokens.dart';

/// Unit coverage for the documented design-token layer (ADR 0040 D1). The whole
/// thesis of pass-1 is PIXEL-STABILITY: every TYPE SCALE role maps to the
/// CURRENT dominant value, so these assertions LOCK the table to those values —
/// if a role's size/weight drifts, adopting it would no longer be pixel-identical
/// and the test fails on purpose.
void main() {
  group('TYPE SCALE maps to current dominant values (pixel-stable)', () {
    test('UI roles', () {
      expect(AppType.body.size, 13);
      expect(AppType.body.weight, FontWeight.w400);
      expect(AppType.body.family, TypeRole.fontUi);

      expect(AppType.title.size, 14);
      expect(AppType.title.weight, FontWeight.w600);

      expect(AppType.titleLg.size, 16);
      expect(AppType.titleLg.weight, FontWeight.w600);

      expect(AppType.label.size, 12.5);
      expect(AppType.caption.size, 11.5);
      expect(AppType.overline.size, 11);
    });

    test('mono roles', () {
      expect(AppType.monoBody.size, 13);
      expect(AppType.monoBody.family, TypeRole.fontMono);
      expect(AppType.monoCaption.size, 11.5);
      expect(AppType.monoCaption.family, TypeRole.fontMono);
    });
  });

  group('role accessor produces a pixel-identical TextStyle', () {
    late BuildContext ctx;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemeData(AppThemeId.night),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
    }

    testWidgets('textBody == ui(size:13,w400) family IBM Plex Sans', (
      tester,
    ) async {
      await pump(tester);
      final s = ctx.textBody();
      expect(s.fontSize, 13);
      expect(s.fontFamily, 'IBM Plex Sans');
      expect(s.fontWeight, FontWeight.w400);
      // Pixel-identical to the raw call it replaces.
      final raw = ctx.ui(size: 13, weight: FontWeight.w400);
      expect(s.fontSize, raw.fontSize);
      expect(s.fontFamily, raw.fontFamily);
      expect(s.fontWeight, raw.fontWeight);
    });

    testWidgets('textTitle/textTitleLg/textLabel weights & sizes', (
      tester,
    ) async {
      await pump(tester);
      expect(ctx.textTitle().fontSize, 14);
      expect(ctx.textTitle().fontWeight, FontWeight.w600);
      expect(ctx.textTitleLg().fontSize, 16);
      expect(ctx.textLabel().fontSize, 12.5);
    });

    testWidgets('monoBody == mono(size:13) family JetBrains Mono', (
      tester,
    ) async {
      await pump(tester);
      final s = ctx.monoBody();
      expect(s.fontSize, 13);
      expect(s.fontFamily, 'JetBrains Mono');
    });

    testWidgets('raw ui/mono API is preserved (call-sites not broken)', (
      tester,
    ) async {
      await pump(tester);
      expect(ctx.ui(size: 15).fontSize, 15); // arbitrary off-scale still works
      expect(ctx.mono(size: 12).fontFamily, 'JetBrains Mono');
    });
  });

  group('Spacing 4pt grid', () {
    test('tokens are on the grid (xxs2 is the only half-step)', () {
      for (final v in Spacing.values) {
        final onGrid = v % 4 == 0 || v == Spacing.xxs2;
        expect(onGrid, isTrue, reason: '$v must be a 4pt multiple or xxs2');
      }
      expect(Spacing.sm8, 8);
      expect(Spacing.md12, 12);
      expect(Spacing.lg16, 16);
      expect(Spacing.xl24, 24);
      expect(Spacing.xxl32, 32);
    });

    testWidgets('Gap renders a sized box', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Gap(Spacing.sm8),
        ),
      );
      final box = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(box.width, 8);
      expect(box.height, 8);
    });
  });

  group('IconSizes + Radii ramp', () {
    test('icon ramp', () {
      expect(IconSizes.sm16, 16);
      expect(IconSizes.md20, 20);
      expect(IconSizes.lg24, 24);
      expect(IconSizes.inline14, 14);
    });

    test('radius scale', () {
      expect(Radii.sm4, 4);
      expect(Radii.md8, 8);
      expect(Radii.lg12, 12);
      expect(Radii.pill, greaterThanOrEqualTo(999));
    });
  });
}
