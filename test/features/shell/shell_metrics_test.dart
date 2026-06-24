import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/shell_metrics.dart';

void main() {
  group('ShellMetrics', () {
    test('rail is the fixed 52px mode switcher (ADR 0030 D1)', () {
      expect(ShellMetrics.railWidth, 52);
      expect(ShellMetrics.railItemSize, 40);
      expect(ShellMetrics.railItemRadius, 9);
      expect(ShellMetrics.railIconSize, 20);
    });

    test('sidebar width clamps to [200, 480] with a 272 default', () {
      expect(ShellMetrics.sidebarDefaultWidth, 272);
      expect(ShellMetrics.clampSidebarWidth(100), 200);
      expect(ShellMetrics.clampSidebarWidth(272), 272);
      expect(ShellMetrics.clampSidebarWidth(999), 480);
    });

    test('collapse snap sits below the min width (hysteresis gap)', () {
      expect(
        ShellMetrics.sidebarCollapseSnap,
        lessThan(ShellMetrics.sidebarMinWidth),
      );
    });
  });

  group('railTooltip', () {
    test('uses ⌘ glyph (no separator) on macOS', () {
      expect(
        railTooltip('Bağlantılar', 1, TargetPlatform.macOS),
        'Bağlantılar  ⌘1',
      );
    });

    test('uses Ctrl+ on other platforms', () {
      expect(
        railTooltip('SFTP', 2, TargetPlatform.windows),
        'SFTP  Ctrl+2',
      );
      expect(
        railTooltip('Vault', 3, TargetPlatform.linux),
        'Vault  Ctrl+3',
      );
    });
  });
}
