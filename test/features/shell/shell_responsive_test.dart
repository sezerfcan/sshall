import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_responsive.dart';

void main() {
  group('ShellBreakpoints — title bar staging (window width)', () {
    test('version label hides below titleVersionHide', () {
      expect(ShellBreakpoints.showVersion(1000), isTrue);
      expect(
        ShellBreakpoints.showVersion(ShellBreakpoints.titleVersionHide),
        isTrue,
      );
      expect(
        ShellBreakpoints.showVersion(ShellBreakpoints.titleVersionHide - 1),
        isFalse,
      );
    });

    test('toolbar collapses into overflow below titleOverflow', () {
      // At exactly the breakpoint the toolbar is still inline (so the 800px
      // widget tests keep finding the inline theme chips / help button).
      expect(
        ShellBreakpoints.titleNeedsOverflow(ShellBreakpoints.titleOverflow),
        isFalse,
      );
      expect(
        ShellBreakpoints.titleNeedsOverflow(ShellBreakpoints.titleOverflow - 1),
        isTrue,
      );
      expect(ShellBreakpoints.titleNeedsOverflow(1200), isFalse);
    });

    test('wordmark hides below titleWordmarkHide', () {
      expect(
        ShellBreakpoints.showWordmark(ShellBreakpoints.titleWordmarkHide),
        isTrue,
      );
      expect(
        ShellBreakpoints.showWordmark(ShellBreakpoints.titleWordmarkHide - 1),
        isFalse,
      );
    });

    test('breakpoints are ordered version > overflow > wordmark', () {
      expect(
        ShellBreakpoints.titleVersionHide,
        greaterThan(ShellBreakpoints.titleOverflow),
      );
      expect(
        ShellBreakpoints.titleOverflow,
        greaterThan(ShellBreakpoints.titleWordmarkHide),
      );
    });
  });

  group('ShellBreakpoints — ADR 0039 title / settings staging', () {
    test('traffic-light gutter is a single named constant (78)', () {
      // The hard-coded `78` literal is gone; the gutter has one source.
      expect(ShellBreakpoints.kMacTrafficLightGutter, 78);
    });

    test('traffic-light gutter collapses in fullscreen', () {
      expect(
        ShellBreakpoints.macTrafficLightGutter(isFullScreen: false),
        ShellBreakpoints.kMacTrafficLightGutter,
      );
      // Fullscreen hides the traffic lights → the gutter narrows to zero so the
      // brand can slide back to the leading edge.
      expect(ShellBreakpoints.macTrafficLightGutter(isFullScreen: true), 0);
    });

    test('showTitle: visible above the threshold, hidden below', () {
      expect(ShellBreakpoints.showTitle(1000), isTrue);
      expect(ShellBreakpoints.showTitle(ShellBreakpoints.titleHide), isTrue);
      expect(
        ShellBreakpoints.showTitle(ShellBreakpoints.titleHide - 1),
        isFalse,
      );
    });

    test('titleSettingsOverflow: gear folds below the threshold', () {
      expect(ShellBreakpoints.titleSettingsOverflow(1000), isFalse);
      expect(
        ShellBreakpoints.titleSettingsOverflow(
          ShellBreakpoints.titleSettingsHide,
        ),
        isFalse,
      );
      expect(
        ShellBreakpoints.titleSettingsOverflow(
          ShellBreakpoints.titleSettingsHide - 1,
        ),
        isTrue,
      );
    });

    test('settings gear folds BEFORE theme/help collapse (D5 ladder order)', () {
      // The Settings gear is more sacrificial than the rest of the trailing
      // cluster, so its threshold sits ABOVE the whole-cluster overflow point.
      expect(
        ShellBreakpoints.titleSettingsHide,
        greaterThan(ShellBreakpoints.titleOverflow),
      );
      // And the centered title is sacrificed before the Settings gear.
      expect(
        ShellBreakpoints.titleHide,
        greaterThan(ShellBreakpoints.titleSettingsHide),
      );
      // Full D5 ordering: version > title > settings > (whole) overflow > wordmark.
      expect(
        ShellBreakpoints.titleVersionHide,
        greaterThan(ShellBreakpoints.titleHide),
      );
    });

    test('staging thresholds are spaced wide enough to need no hysteresis', () {
      // The title-bar thresholds are deliberately spaced (≥40px apart) so a
      // resize never flickers a control on a boundary — there is no explicit
      // hysteresis band (ADR 0039 D5). Guard the spacing so it cannot regress.
      final ordered = [
        ShellBreakpoints.titleVersionHide, // 940
        ShellBreakpoints.titleHide, // 880
        ShellBreakpoints.titleSettingsHide, // 840
        ShellBreakpoints.titleOverflow, // 800
      ];
      for (var i = 1; i < ordered.length; i++) {
        expect(
          ordered[i - 1] - ordered[i],
          greaterThanOrEqualTo(40),
          reason: 'adjacent staging thresholds must stay ≥40px apart',
        );
      }
    });
  });

  group('tabPillMode — panel-width driven pill density', () {
    test('wide panel: full title width, not icon-only', () {
      final m = tabPillMode(600);
      expect(m.iconOnly, isFalse);
      expect(m.maxTitleWidth, 160);
    });

    test('title width shrinks monotonically as the panel narrows', () {
      final widths = [
        600.0,
        420.0,
        320.0,
        240.0,
      ].map((w) => tabPillMode(w).maxTitleWidth).toList();
      for (var i = 1; i < widths.length; i++) {
        expect(widths[i], lessThanOrEqualTo(widths[i - 1]));
      }
      // None of these are icon-only yet (still showing a (shrunken) title).
      for (final w in [600.0, 420.0, 320.0, 240.0]) {
        expect(
          tabPillMode(w).iconOnly,
          isFalse,
          reason: 'panel $w should keep a title',
        );
      }
    });

    test('very narrow panel: icon-only (title moves to tooltip)', () {
      final m = tabPillMode(180);
      expect(m.iconOnly, isTrue);
    });
  });

  test('detach edge threshold is a small positive inset', () {
    expect(kDetachEdgeThreshold, greaterThan(0));
    expect(kDetachEdgeThreshold, lessThan(40));
  });
}
