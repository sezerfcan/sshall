import 'package:flutter/material.dart';
import '../../theme/context_ext.dart';

/// Placeholder rows shown while a pane's first listing loads (D6). Replaces the
/// whole-list `CircularProgressIndicator` with content-shaped grey bars so the
/// layout does not jump when the real rows arrive. No animation package — a
/// static, low-contrast placeholder is enough and avoids a new dependency.
class FilePaneSkeleton extends StatelessWidget {
  /// Whether to reserve a permissions column placeholder (remote pane).
  final bool showPermissions;
  final int rows;

  const FilePaneSkeleton({
    super.key,
    this.showPermissions = false,
    this.rows = 8,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListView.builder(
      key: const Key('filePaneSkeleton'),
      itemCount: rows,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (ctx, i) {
        // Vary the name-bar width a little so it reads as a list, not a grid.
        final nameFlex = 3 + (i % 3);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              _box(c.border, 16, 16),
              const SizedBox(width: 8),
              Expanded(flex: nameFlex, child: _bar(c.border)),
              Expanded(flex: 6 - nameFlex, child: const SizedBox()),
              const SizedBox(width: 12),
              SizedBox(width: 56, child: _bar(c.border)),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: _bar(c.border)),
              if (showPermissions) ...[
                const SizedBox(width: 12),
                SizedBox(width: 90, child: _bar(c.border)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color color) => Container(
    height: 9,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );

  Widget _box(Color color, double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
